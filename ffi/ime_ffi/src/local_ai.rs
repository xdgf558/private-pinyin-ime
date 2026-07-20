use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use ime_core::{Candidate, CandidateSource, ImeOutput, InputSession};
use private_pinyin_local_ai_core::{
    AiBudget, AiCandidateInput, AiCandidateSetHash, AiCompositionRevision, AiDeadline, AiFeature,
    AiFeaturePolicy, AiLiteCandidateFeatures, AiLiteRanker, AiPrivacyMode, AiRawInputKind,
    AiRequestBuilder, AiRequestId, AiRequestIdentity, AiSessionId, AiStatus, AiSubmitStatus,
    BoundedAiWorker, HardwareProfile, HardwareTier, ModelPackageVerifier, ModelPlatform,
    PrivacyGuard,
};

static NEXT_AI_SESSION_ID: AtomicU64 = AtomicU64::new(1);

pub(crate) struct LocalAiRuntime {
    worker: Arc<BoundedAiWorker>,
    hardware_tier: HardwareTier,
}

impl LocalAiRuntime {
    pub(crate) fn new(
        platform: ModelPlatform,
        physical_memory_mb: u64,
        gpu_available: bool,
    ) -> Option<Arc<Self>> {
        let hardware = HardwareProfile::new(
            physical_memory_mb.saturating_mul(1024 * 1024),
            gpu_available,
        );
        let package = ModelPackageVerifier::new(platform, hardware)
            .ok()?
            .verify_embedded_ai_lite()
            .ok()?;
        let provider = Arc::new(AiLiteRanker::from_verified_package(&package).ok()?);
        let worker = Arc::new(BoundedAiWorker::new(provider).ok()?);
        Some(Arc::new(Self {
            worker,
            hardware_tier: hardware.tier(),
        }))
    }
}

pub(crate) struct LocalAiSession {
    runtime: Arc<LocalAiRuntime>,
    session_id: AiSessionId,
    revision: u64,
    next_request_id: u64,
    secure_input: bool,
    last_visible: Option<CompositionSnapshot>,
    inflight: Option<InflightRequest>,
    ready: Option<ReadyRanking>,
}

#[derive(Clone, PartialEq, Eq)]
struct CompositionSnapshot {
    preedit: String,
    candidate_texts: Vec<String>,
}

struct InflightRequest {
    identity: AiRequestIdentity,
    deadline: AiDeadline,
    candidate_texts: Vec<String>,
}

struct ReadyRanking {
    identity: AiRequestIdentity,
    deadline: AiDeadline,
    candidate_texts: Vec<String>,
    order: Vec<usize>,
}

impl LocalAiSession {
    pub(crate) fn new(runtime: Arc<LocalAiRuntime>) -> Self {
        let sequence = NEXT_AI_SESSION_ID.fetch_add(1, Ordering::Relaxed);
        let process = u128::from(std::process::id());
        Self {
            runtime,
            session_id: AiSessionId::from_u128((process << 64) | u128::from(sequence)),
            revision: 0,
            next_request_id: 1,
            secure_input: false,
            last_visible: None,
            inflight: None,
            ready: None,
        }
    }

    pub(crate) fn set_secure_input(&mut self, secure_input: bool) {
        if self.secure_input == secure_input {
            return;
        }
        self.secure_input = secure_input;
        if secure_input {
            self.cancel_inflight();
            self.ready = None;
        }
    }

    pub(crate) fn process_output(&mut self, session: &mut InputSession, output: &mut ImeOutput) {
        self.poll_completion();

        let before_rerank = snapshot(output);
        let revision_changed = self
            .last_visible
            .as_ref()
            .is_none_or(|previous| previous != &before_rerank);
        if revision_changed {
            self.revision = self.revision.saturating_add(1);
            self.cancel_inflight();
        }

        let applied_staged = revision_changed && self.apply_ready(session, output, false);
        if !applied_staged
            && revision_changed
            && self.should_submit(session, output)
            && self.submit(session, output)
        {
            // The approved Lite model is tiny. Poll once without waiting so a result that
            // already finished can be applied before this page is ever visible.
            self.poll_completion();
            let _ = self.apply_ready(session, output, true);
        }

        self.last_visible = Some(snapshot(output));
    }

    fn should_submit(&self, session: &InputSession, output: &ImeOutput) -> bool {
        !self.secure_input
            && !output.candidates.is_empty()
            && (!session.raw_input.is_empty() || !session.nine_key_input.is_empty())
    }

    fn submit(&mut self, session: &InputSession, output: &ImeOutput) -> bool {
        let candidate_texts = output
            .candidates
            .iter()
            .map(|candidate| candidate.text.clone())
            .collect::<Vec<_>>();
        let identity = AiRequestIdentity::new(
            self.session_id,
            AiRequestId::new(self.next_request_id),
            AiCompositionRevision::new(self.revision),
            AiCandidateSetHash::from_ordered_texts(&candidate_texts),
        );
        self.next_request_id = self.next_request_id.saturating_add(1);

        let raw_input_kind = if session.nine_key_input.is_empty() {
            AiRawInputKind::FullPinyin
        } else {
            AiRawInputKind::NineKeyDigits
        };
        let raw_input = if session.nine_key_input.is_empty() {
            &session.raw_input
        } else {
            &session.nine_key_input
        };
        let request_candidates = build_candidate_inputs(session, &output.candidates);
        let privacy_mode = if session.privacy_mode {
            AiPrivacyMode::Strict
        } else {
            AiPrivacyMode::Standard
        };
        let request = AiRequestBuilder::new(
            identity,
            AiFeature::CandidateRerank,
            "zh-Hans",
            self.runtime.hardware_tier,
            AiBudget::for_feature(AiFeature::CandidateRerank),
        )
        .with_raw_input_kind(raw_input_kind)
        .with_raw_pinyin(raw_input)
        .with_composition_text(&output.preedit)
        .with_base_candidates(request_candidates)
        .with_recent_tokens(session.context_tokens.clone())
        .with_privacy_mode(privacy_mode)
        .with_secure_input(self.secure_input)
        .build(&PrivacyGuard, AiFeaturePolicy::approved_model_enabled(true));
        let Ok(request) = request else {
            return false;
        };
        let deadline = request.deadline();

        if self.runtime.worker.try_submit(request) != AiSubmitStatus::Accepted {
            return false;
        }
        self.inflight = Some(InflightRequest {
            identity,
            deadline,
            candidate_texts,
        });
        true
    }

    fn poll_completion(&mut self) {
        let Some(inflight) = self.inflight.take() else {
            return;
        };
        let Some(completion) = self.runtime.worker.take_completed(inflight.identity) else {
            self.inflight = Some(inflight);
            return;
        };
        let Ok(response) = completion.into_result() else {
            return;
        };
        if !response.matches(inflight.identity) || response.status() != AiStatus::Completed {
            return;
        }
        let Some(order) =
            complete_candidate_order(&inflight.candidate_texts, response.candidates())
        else {
            return;
        };
        self.ready = Some(ReadyRanking {
            identity: inflight.identity,
            deadline: inflight.deadline,
            candidate_texts: inflight.candidate_texts,
            order,
        });
    }

    fn apply_ready(
        &mut self,
        session: &mut InputSession,
        output: &mut ImeOutput,
        allow_same_revision: bool,
    ) -> bool {
        let Some(ready) = self.ready.take() else {
            return false;
        };
        let current_texts = output
            .candidates
            .iter()
            .map(|candidate| candidate.text.clone())
            .collect::<Vec<_>>();
        let source_revision = ready.identity.composition_revision().get();
        let revision_matches = source_revision < self.revision
            || (allow_same_revision && source_revision == self.revision);
        if ready.deadline.is_expired()
            || !ready.identity.matches_current(
                self.session_id,
                AiCompositionRevision::new(source_revision),
                AiCandidateSetHash::from_ordered_texts(&current_texts),
            )
            || !revision_matches
            || ready.candidate_texts != current_texts
            || !session.reorder_current_candidate_page(&ready.order)
        {
            return false;
        }

        let original = output.candidates.clone();
        output.candidates = ready
            .order
            .iter()
            .map(|&index| original[index].clone())
            .collect();
        true
    }

    fn cancel_inflight(&mut self) {
        if let Some(inflight) = self.inflight.take() {
            self.runtime.worker.cancel(inflight.identity);
        }
    }
}

impl Drop for LocalAiSession {
    fn drop(&mut self) {
        self.cancel_inflight();
    }
}

fn snapshot(output: &ImeOutput) -> CompositionSnapshot {
    CompositionSnapshot {
        preedit: output.preedit.clone(),
        candidate_texts: output
            .candidates
            .iter()
            .map(|candidate| candidate.text.clone())
            .collect(),
    }
}

fn build_candidate_inputs(
    session: &InputSession,
    candidates: &[Candidate],
) -> Vec<AiCandidateInput> {
    let (minimum_score, maximum_score) = candidates.iter().fold(
        (f64::INFINITY, f64::NEG_INFINITY),
        |(minimum, maximum), candidate| {
            if candidate.rank_score.is_finite() {
                (
                    minimum.min(candidate.rank_score),
                    maximum.max(candidate.rank_score),
                )
            } else {
                (minimum, maximum)
            }
        },
    );

    candidates
        .iter()
        .enumerate()
        .map(|(rank, candidate)| {
            let frequency = if candidate.source == CandidateSource::User {
                1_000
            } else {
                normalized_score(candidate.rank_score, minimum_score, maximum_score)
            };
            let expected_segments = session.parsed_syllables.len().max(1);
            let segmentation = if candidate.segments.len() == expected_segments {
                1_000
            } else if !candidate.segments.is_empty() {
                600
            } else {
                0
            };
            let prediction = candidate.source == CandidateSource::Prediction;
            let bigram = u16::from(prediction && !session.context_tokens.is_empty()) * 1_000;
            let trigram = u16::from(prediction && session.context_tokens.len() >= 2) * 1_000;
            let features =
                AiLiteCandidateFeatures::new(frequency, segmentation, bigram, trigram, 0, 0)
                    .unwrap_or_default();
            AiCandidateInput::new(&candidate.text, rank)
                .with_pinyin(&candidate.pinyin)
                .with_base_score(clamped_base_score(candidate.rank_score))
                .with_lite_features(features)
        })
        .collect()
}

fn normalized_score(score: f64, minimum: f64, maximum: f64) -> u16 {
    if !score.is_finite() || !minimum.is_finite() || !maximum.is_finite() {
        return 0;
    }
    let range = maximum - minimum;
    if range <= f64::EPSILON {
        return 500;
    }
    (((score - minimum) / range) * 1_000.0)
        .round()
        .clamp(0.0, 1_000.0) as u16
}

fn clamped_base_score(score: f64) -> i64 {
    if !score.is_finite() {
        return 0;
    }
    (score * 1_000.0).round().clamp(-1.0e12, 1.0e12) as i64
}

fn complete_candidate_order(
    candidate_texts: &[String],
    ranked: &[private_pinyin_local_ai_core::AiCandidateOutput],
) -> Option<Vec<usize>> {
    let mut seen = vec![false; candidate_texts.len()];
    let mut order = Vec::with_capacity(candidate_texts.len());
    for candidate in ranked {
        let index = candidate.base_index()?;
        if index >= candidate_texts.len()
            || seen[index]
            || candidate.text() != candidate_texts[index]
        {
            return None;
        }
        seen[index] = true;
        order.push(index);
    }
    order.extend(
        seen.iter()
            .enumerate()
            .filter_map(|(index, was_seen)| (!was_seen).then_some(index)),
    );
    Some(order)
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use ime_core::{ImeEngine, KeyEvent};
    use private_pinyin_local_ai_core::{AiCandidateOutput, AiReasonCode};

    use super::*;

    #[test]
    fn partial_ai_order_keeps_every_unranked_candidate_stable() {
        let texts = vec!["a".to_string(), "b".to_string(), "c".to_string()];
        let ranked = vec![
            AiCandidateOutput::new("c", Some(2), 5, AiReasonCode::LiteTrigram),
            AiCandidateOutput::new("a", Some(0), 3, AiReasonCode::LiteFrequency),
        ];
        assert_eq!(
            complete_candidate_order(&texts, &ranked),
            Some(vec![2, 0, 1])
        );
    }

    #[test]
    fn mismatched_or_duplicate_ai_indices_fail_closed() {
        let texts = vec!["a".to_string(), "b".to_string()];
        assert!(complete_candidate_order(
            &texts,
            &[AiCandidateOutput::new(
                "wrong",
                Some(0),
                0,
                AiReasonCode::LiteBaseOrder,
            )]
        )
        .is_none());
        assert!(complete_candidate_order(
            &texts,
            &[
                AiCandidateOutput::new("a", Some(0), 0, AiReasonCode::LiteBaseOrder),
                AiCandidateOutput::new("a", Some(0), 0, AiReasonCode::LiteBaseOrder),
            ]
        )
        .is_none());
    }

    #[test]
    fn expired_ready_ranking_never_reorders_a_matching_candidate_page() {
        let engine = ImeEngine::new().expect("engine");
        let mut input_session = engine.create_session();
        let _ = input_session.feed_key(KeyEvent::from_char('n'));
        let mut output = input_session.feed_key(KeyEvent::from_char('i'));
        assert!(output.candidates.len() >= 2);

        let runtime = LocalAiRuntime::new(ModelPlatform::Macos, 8 * 1024, false)
            .expect("approved embedded ranker");
        let mut ai_session = LocalAiSession::new(runtime);
        ai_session.revision = 2;
        let candidate_texts = output
            .candidates
            .iter()
            .map(|candidate| candidate.text.clone())
            .collect::<Vec<_>>();
        let before = candidate_texts.clone();
        let mut order = (0..candidate_texts.len()).collect::<Vec<_>>();
        order.reverse();
        ai_session.ready = Some(ReadyRanking {
            identity: AiRequestIdentity::new(
                ai_session.session_id,
                AiRequestId::new(1),
                AiCompositionRevision::new(1),
                AiCandidateSetHash::from_ordered_texts(&candidate_texts),
            ),
            deadline: AiDeadline::from_start(
                Instant::now() - Duration::from_secs(1),
                Duration::from_millis(1),
            ),
            candidate_texts,
            order,
        });

        assert!(!ai_session.apply_ready(&mut input_session, &mut output, false));
        let after = input_session
            .current_page_candidates_snapshot()
            .into_iter()
            .map(|candidate| candidate.text)
            .collect::<Vec<_>>();
        assert_eq!(after, before);
    }
}
