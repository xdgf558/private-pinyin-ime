use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::Instant;

use serde::Deserialize;

use crate::{
    AiCandidateInput, AiCandidateOutput, AiError, AiErrorCode, AiFeature, AiFeaturePolicy,
    AiReasonCode, AiRequest, AiRequestIdentity, AiResponse, AiStatus, LocalAiProvider, ModelClass,
    ModelRuntime, PrivacyGuard, ProviderHealth, VerifiedModelPackage,
};

pub const AI_LITE_MODEL_SCHEMA_VERSION: u32 = 1;
pub const AI_LITE_FEATURE_SCALE: u16 = crate::request::AI_LITE_FEATURE_SCALE;
pub const MAX_AI_LITE_RANKER_MODEL_BYTES: u64 = 64 * 1024;

const PROVIDER_ID: &str = "private-pinyin-ai-lite-ranker-v1";
const CAPABILITIES: [AiFeature; 1] = [AiFeature::CandidateRerank];
const MAX_ABS_INTERCEPT_MILLI: i32 = 10_000;
const MAX_WEIGHT_MILLI: i32 = 10_000;
const MAX_CANCELLED_IDENTITIES: usize = 256;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
struct AiLiteRankerModel {
    schema_version: u32,
    model_id: String,
    model_version: String,
    feature_scale: u16,
    intercept_milli: i32,
    weights_milli: AiLiteRankerWeights,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
struct AiLiteRankerWeights {
    base_rank: i32,
    base_score: i32,
    frequency: i32,
    segmentation: i32,
    bigram: i32,
    trigram: i32,
    typo_correction: i32,
    term_preservation: i32,
}

impl AiLiteRankerModel {
    fn parse(bytes: &[u8], expected_id: &str, expected_version: &str) -> Result<Self, AiError> {
        let model = serde_json::from_slice::<Self>(bytes).map_err(|_| model_format_invalid())?;
        if model.schema_version != AI_LITE_MODEL_SCHEMA_VERSION
            || model.model_id != expected_id
            || model.model_version != expected_version
            || model.feature_scale != AI_LITE_FEATURE_SCALE
            || model.intercept_milli.unsigned_abs() > MAX_ABS_INTERCEPT_MILLI as u32
            || !model.weights_milli.is_valid()
        {
            return Err(model_format_invalid());
        }
        Ok(model)
    }
}

impl AiLiteRankerWeights {
    fn is_valid(self) -> bool {
        let weights = [
            self.base_rank,
            self.base_score,
            self.frequency,
            self.segmentation,
            self.bigram,
            self.trigram,
            self.typo_correction,
            self.term_preservation,
        ];
        weights
            .iter()
            .all(|weight| (0..=MAX_WEIGHT_MILLI).contains(weight))
            && self.base_rank > 0
            && weights[2..].iter().any(|weight| *weight > 0)
    }
}

pub struct AiLiteRanker {
    model: AiLiteRankerModel,
    cancelled: Mutex<VecDeque<AiRequestIdentity>>,
}

impl AiLiteRanker {
    pub fn from_verified_package(package: &VerifiedModelPackage) -> Result<Self, AiError> {
        let manifest = package.manifest();
        if manifest.class() != ModelClass::Lite
            || manifest.runtime() != ModelRuntime::RustCompact
            || manifest.capabilities() != CAPABILITIES
        {
            return Err(model_format_invalid());
        }
        let bytes = package.read_primary_model_bytes(MAX_AI_LITE_RANKER_MODEL_BYTES)?;
        let model = AiLiteRankerModel::parse(&bytes, manifest.id(), manifest.version())?;
        Ok(Self {
            model,
            cancelled: Mutex::new(VecDeque::new()),
        })
    }

    pub fn model_id(&self) -> &str {
        &self.model.model_id
    }

    pub fn model_version(&self) -> &str {
        &self.model.model_version
    }

    fn is_cancelled(&self, identity: AiRequestIdentity) -> Result<bool, AiError> {
        self.cancelled
            .lock()
            .map(|identities| identities.contains(&identity))
            .map_err(|_| AiError::new(AiErrorCode::Internal))
    }

    #[cfg(test)]
    fn cancelled_identity_count(&self) -> usize {
        self.cancelled
            .lock()
            .map(|identities| identities.len())
            .unwrap_or(MAX_CANCELLED_IDENTITIES)
    }
}

impl LocalAiProvider for AiLiteRanker {
    fn provider_id(&self) -> &'static str {
        PROVIDER_ID
    }

    fn capabilities(&self) -> &'static [AiFeature] {
        &CAPABILITIES
    }

    fn health(&self) -> ProviderHealth {
        ProviderHealth::Available
    }

    fn infer(&self, request: &AiRequest) -> Result<AiResponse, AiError> {
        if request.feature() != AiFeature::CandidateRerank {
            return Err(AiError::new(AiErrorCode::FeatureUnsupported));
        }
        PrivacyGuard.validate(request, AiFeaturePolicy::approved_model_enabled(true))?;
        if self.is_cancelled(request.identity())? {
            return Err(AiError::new(AiErrorCode::Cancelled));
        }

        let started_at = Instant::now();
        let candidates = request.base_candidates();
        if candidates.is_empty() {
            return Ok(AiResponse::new(
                request.identity(),
                request.feature(),
                AiStatus::NoSuggestion,
                Vec::new(),
                started_at.elapsed(),
                self.provider_id(),
            ));
        }

        let (minimum_base_score, maximum_base_score) =
            candidates
                .iter()
                .fold((i64::MAX, i64::MIN), |(minimum, maximum), candidate| {
                    (
                        minimum.min(candidate.base_score()),
                        maximum.max(candidate.base_score()),
                    )
                });
        let mut ranked = Vec::with_capacity(candidates.len());
        for (base_index, candidate) in candidates.iter().enumerate() {
            if request.deadline().is_expired() {
                return Err(AiError::new(AiErrorCode::Timeout));
            }
            if self.is_cancelled(request.identity())? {
                return Err(AiError::new(AiErrorCode::Cancelled));
            }
            if !candidate.lite_features().is_valid() {
                return Err(AiError::new(AiErrorCode::RankerFeatureInvalid));
            }
            ranked.push(score_candidate(
                &self.model,
                candidate,
                base_index,
                candidates.len(),
                minimum_base_score,
                maximum_base_score,
            ));
        }

        ranked.sort_by(|left, right| {
            right
                .total_score_milli
                .cmp(&left.total_score_milli)
                .then_with(|| left.base_rank.cmp(&right.base_rank))
                .then_with(|| left.base_index.cmp(&right.base_index))
        });
        if request.deadline().is_expired() {
            return Err(AiError::new(AiErrorCode::Timeout));
        }
        if self.is_cancelled(request.identity())? {
            return Err(AiError::new(AiErrorCode::Cancelled));
        }

        let output_limit = request
            .budget()
            .max_suggestions()
            .min(request.budget().max_candidates())
            .min(ranked.len());
        let output = ranked
            .into_iter()
            .take(output_limit)
            .map(|candidate| {
                AiCandidateOutput::new(
                    candidates[candidate.base_index].text(),
                    Some(candidate.base_index),
                    clamp_i64_to_i32(candidate.adjustment_milli),
                    candidate.reason,
                )
            })
            .collect::<Vec<_>>();
        Ok(AiResponse::new(
            request.identity(),
            request.feature(),
            AiStatus::Completed,
            output,
            started_at.elapsed(),
            self.provider_id(),
        ))
    }

    fn cancel(&self, identity: AiRequestIdentity) {
        if let Ok(mut identities) = self.cancelled.lock() {
            if identities.contains(&identity) {
                return;
            }
            if identities.len() == MAX_CANCELLED_IDENTITIES {
                identities.pop_front();
            }
            identities.push_back(identity);
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct RankedCandidate {
    base_index: usize,
    base_rank: usize,
    total_score_milli: i64,
    adjustment_milli: i64,
    reason: AiReasonCode,
}

fn score_candidate(
    model: &AiLiteRankerModel,
    candidate: &AiCandidateInput,
    base_index: usize,
    candidate_count: usize,
    minimum_base_score: i64,
    maximum_base_score: i64,
) -> RankedCandidate {
    let weights = model.weights_milli;
    let rank_prior = normalized_rank_prior(candidate.base_rank(), candidate_count);
    let base_score_prior = normalized_base_score(
        candidate.base_score(),
        minimum_base_score,
        maximum_base_score,
    );
    let features = candidate.lite_features();
    let base_rank_component = weighted_component(weights.base_rank, rank_prior);
    let base_score_component = weighted_component(weights.base_score, base_score_prior);
    let feature_components = [
        (
            weighted_component(weights.frequency, features.frequency()),
            AiReasonCode::LiteFrequency,
        ),
        (
            weighted_component(weights.segmentation, features.segmentation()),
            AiReasonCode::LiteSegmentation,
        ),
        (
            weighted_component(weights.bigram, features.bigram()),
            AiReasonCode::LiteBigram,
        ),
        (
            weighted_component(weights.trigram, features.trigram()),
            AiReasonCode::LiteTrigram,
        ),
        (
            weighted_component(weights.typo_correction, features.typo_correction()),
            AiReasonCode::LiteTypoCorrection,
        ),
        (
            weighted_component(weights.term_preservation, features.term_preservation()),
            AiReasonCode::LiteTermPreservation,
        ),
    ];
    let adjustment_milli = feature_components
        .iter()
        .map(|(score, _)| *score)
        .sum::<i64>();
    let (dominant_feature_score, dominant_feature_reason) = feature_components
        .iter()
        .copied()
        .max_by_key(|(score, _)| *score)
        .unwrap_or((0, AiReasonCode::LiteBaseOrder));
    let base_component = base_rank_component.max(base_score_component);
    let reason = if dominant_feature_score > base_component {
        dominant_feature_reason
    } else {
        AiReasonCode::LiteBaseOrder
    };

    RankedCandidate {
        base_index,
        base_rank: candidate.base_rank(),
        total_score_milli: i64::from(model.intercept_milli)
            + base_rank_component
            + base_score_component
            + adjustment_milli,
        adjustment_milli,
        reason,
    }
}

fn normalized_rank_prior(base_rank: usize, candidate_count: usize) -> u16 {
    if candidate_count <= 1 {
        return AI_LITE_FEATURE_SCALE;
    }
    let bounded_rank = base_rank.min(candidate_count - 1);
    let numerator = (candidate_count - 1 - bounded_rank) * usize::from(AI_LITE_FEATURE_SCALE);
    u16::try_from(numerator / (candidate_count - 1)).unwrap_or(AI_LITE_FEATURE_SCALE)
}

fn normalized_base_score(score: i64, minimum: i64, maximum: i64) -> u16 {
    if minimum >= maximum {
        return AI_LITE_FEATURE_SCALE;
    }
    let numerator = (i128::from(score) - i128::from(minimum)) * i128::from(AI_LITE_FEATURE_SCALE);
    let denominator = i128::from(maximum) - i128::from(minimum);
    u16::try_from((numerator / denominator).clamp(0, i128::from(AI_LITE_FEATURE_SCALE)))
        .unwrap_or_default()
}

fn weighted_component(weight_milli: i32, value: u16) -> i64 {
    i64::from(weight_milli) * i64::from(value) / i64::from(AI_LITE_FEATURE_SCALE)
}

fn clamp_i64_to_i32(value: i64) -> i32 {
    value.clamp(i64::from(i32::MIN), i64::from(i32::MAX)) as i32
}

fn model_format_invalid() -> AiError {
    AiError::new(AiErrorCode::ModelFormatInvalid)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        AiBudget, AiCandidateSetHash, AiCompositionRevision, AiLiteCandidateFeatures,
        AiRequestBuilder, AiRequestId, AiSessionId, HardwareTier,
    };

    fn model() -> AiLiteRankerModel {
        AiLiteRankerModel::parse(
            br#"{
                "schema_version": 1,
                "model_id": "private-pinyin.test-ranker",
                "model_version": "1.0.0",
                "feature_scale": 1000,
                "intercept_milli": 0,
                "weights_milli": {
                    "base_rank": 400,
                    "base_score": 250,
                    "frequency": 350,
                    "segmentation": 500,
                    "bigram": 700,
                    "trigram": 900,
                    "typo_correction": 650,
                    "term_preservation": 850
                }
            }"#,
            "private-pinyin.test-ranker",
            "1.0.0",
        )
        .expect("valid test ranker")
    }

    fn ranker() -> AiLiteRanker {
        AiLiteRanker {
            model: model(),
            cancelled: Mutex::new(VecDeque::new()),
        }
    }

    fn request(candidates: Vec<AiCandidateInput>) -> AiRequest {
        let identity = AiRequestIdentity::new(
            AiSessionId::from_u128(1),
            AiRequestId::new(1),
            AiCompositionRevision::new(1),
            AiCandidateSetHash::from_ordered_texts(candidates.iter().map(AiCandidateInput::text)),
        );
        AiRequestBuilder::new(
            identity,
            AiFeature::CandidateRerank,
            "zh-Hans",
            HardwareTier::Tier1,
            AiBudget::for_feature(AiFeature::CandidateRerank),
        )
        .with_base_candidates(candidates)
        .build(&PrivacyGuard, AiFeaturePolicy::approved_model_enabled(true))
        .expect("guarded ranker request")
    }

    #[test]
    fn contextual_signal_can_promote_a_lower_base_candidate() {
        let candidates = vec![
            AiCandidateInput::new("天气", 0).with_base_score(100),
            AiCandidateInput::new("预报", 1)
                .with_base_score(90)
                .with_lite_features(
                    AiLiteCandidateFeatures::new(0, 0, 1_000, 1_000, 0, 0)
                        .expect("bounded features"),
                ),
        ];
        let response = ranker().infer(&request(candidates)).expect("rank response");
        assert_eq!(response.candidates()[0].text(), "预报");
        assert_eq!(
            response.candidates()[0].reason_code(),
            AiReasonCode::LiteTrigram
        );
        assert_eq!(response.candidates()[0].base_index(), Some(1));
    }

    #[test]
    fn equal_scores_keep_base_rank_and_index_stable() {
        let candidates = vec![
            AiCandidateInput::new("甲", 0).with_base_score(100),
            AiCandidateInput::new("乙", 0).with_base_score(100),
            AiCandidateInput::new("丙", 2).with_base_score(90),
        ];
        let response = ranker().infer(&request(candidates)).expect("rank response");
        assert_eq!(response.candidates()[0].text(), "甲");
        assert_eq!(response.candidates()[1].text(), "乙");
    }

    #[test]
    fn model_parser_rejects_unknown_fields_and_manifest_mismatch() {
        let unknown = br#"{
            "schema_version":1,"model_id":"id","model_version":"1","feature_scale":1000,
            "intercept_milli":0,"weights_milli":{"base_rank":1,"base_score":1,
            "frequency":1,"segmentation":1,"bigram":1,"trigram":1,
            "typo_correction":1,"term_preservation":1},"unexpected":true
        }"#;
        assert_eq!(
            AiLiteRankerModel::parse(unknown, "id", "1")
                .expect_err("unknown field must fail")
                .code(),
            AiErrorCode::ModelFormatInvalid
        );
        assert_eq!(
            AiLiteRankerModel::parse(
                br#"{"schema_version":1,"model_id":"id","model_version":"1","feature_scale":1000,"intercept_milli":0,"weights_milli":{"base_rank":1,"base_score":1,"frequency":1,"segmentation":1,"bigram":1,"trigram":1,"typo_correction":1,"term_preservation":1}}"#,
                "different",
                "1",
            )
            .expect_err("manifest identity mismatch must fail")
            .code(),
            AiErrorCode::ModelFormatInvalid
        );
        assert_eq!(
            AiLiteRankerModel::parse(
                br#"{"schema_version":1,"model_id":"id","model_version":"1","feature_scale":1000,"intercept_milli":-2147483648,"weights_milli":{"base_rank":1,"base_score":1,"frequency":1,"segmentation":1,"bigram":1,"trigram":1,"typo_correction":1,"term_preservation":1}}"#,
                "id",
                "1",
            )
            .expect_err("minimum intercept must fail without overflowing")
            .code(),
            AiErrorCode::ModelFormatInvalid
        );
    }

    #[test]
    fn cancelled_identity_storage_is_bounded() {
        let provider = ranker();
        for request_id in 0..(MAX_CANCELLED_IDENTITIES as u64 + 20) {
            provider.cancel(AiRequestIdentity::new(
                AiSessionId::from_u128(1),
                AiRequestId::new(request_id),
                AiCompositionRevision::new(1),
                AiCandidateSetHash::from_ordered_texts([request_id.to_string()]),
            ));
        }
        assert_eq!(
            provider.cancelled_identity_count(),
            MAX_CANCELLED_IDENTITIES
        );
    }

    #[test]
    fn thirty_two_candidate_inference_stays_inside_the_approved_budget() {
        let candidates = (0..32)
            .map(|index| {
                AiCandidateInput::new(format!("候选{index}"), index)
                    .with_base_score(1_000 - index as i64)
                    .with_lite_features(
                        AiLiteCandidateFeatures::new(
                            (index * 31) as u16,
                            (index * 23) as u16,
                            (index * 17) as u16,
                            (index * 11) as u16,
                            (index * 7) as u16,
                            (index * 5) as u16,
                        )
                        .expect("bounded test features"),
                    )
            })
            .collect::<Vec<_>>();
        let response = ranker()
            .infer(&request(candidates))
            .expect("bounded rank response");

        assert_eq!(response.candidates().len(), 3);
        assert!(response.elapsed() < std::time::Duration::from_millis(30));
    }
}
