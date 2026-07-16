use std::time::{Duration, Instant};

use crate::{
    AiBudget, AiCandidateInput, AiCandidateSetHash, AiCompositionRevision, AiErrorCode, AiFeature,
    AiFeaturePolicy, AiRequest, AiRequestBuilder, AiRequestId, AiRequestIdentity, AiSessionId,
    HardwareTier, LocalAiProvider, MockProvider, PrivacyGuard,
};

fn candidates() -> Vec<AiCandidateInput> {
    vec![
        AiCandidateInput::new("你好", 0)
            .with_pinyin("ni hao")
            .with_base_score(100),
        AiCandidateInput::new("你号", 1)
            .with_pinyin("ni hao")
            .with_base_score(80),
    ]
}

fn identity(
    session: u128,
    request: u64,
    revision: u64,
    candidates: &[AiCandidateInput],
) -> AiRequestIdentity {
    AiRequestIdentity::new(
        AiSessionId::from_u128(session),
        AiRequestId::new(request),
        AiCompositionRevision::new(revision),
        AiCandidateSetHash::from_ordered_texts(candidates.iter().map(AiCandidateInput::text)),
    )
}

fn request(identity: AiRequestIdentity, candidates: Vec<AiCandidateInput>) -> AiRequest {
    AiRequestBuilder::new(
        identity,
        AiFeature::CandidateRerank,
        "zh-Hans",
        HardwareTier::Tier1,
        AiBudget::for_feature(AiFeature::CandidateRerank),
    )
    .with_raw_pinyin("nihao")
    .with_composition_text("你好")
    .with_base_candidates(candidates)
    .with_recent_tokens(vec!["今天".to_owned(), "天气".to_owned()])
    .build(&PrivacyGuard, AiFeaturePolicy::local_rules_enabled(true))
    .expect("guarded mock request")
}

#[test]
fn candidate_set_hash_is_deterministic_and_order_sensitive() {
    let first = AiCandidateSetHash::from_ordered_texts(["你好", "你号"]);
    let same = AiCandidateSetHash::from_ordered_texts(["你好", "你号"]);
    let reordered = AiCandidateSetHash::from_ordered_texts(["你号", "你好"]);

    assert_eq!(first, same);
    assert_ne!(first, reordered);
}

#[test]
fn mock_provider_is_deterministic_and_preserves_identity() {
    let candidates = candidates();
    let identity = identity(1, 7, 3, &candidates);
    let request = request(identity, candidates);
    let provider = MockProvider::default();

    let first = provider.infer(&request).expect("first mock response");
    let second = provider.infer(&request).expect("second mock response");

    assert_eq!(first, second);
    assert!(first.matches(identity));
    assert_eq!(first.candidates().len(), 2);
    assert_eq!(first.candidates()[0].text(), "你好");
}

#[test]
fn cancellation_is_scoped_to_the_complete_request_identity() {
    let candidates = candidates();
    let cancelled_identity = identity(1, 9, 4, &candidates);
    let next_revision_identity = identity(1, 9, 5, &candidates);
    let provider = MockProvider::default();
    provider.cancel(cancelled_identity);

    let cancelled = provider
        .infer(&request(cancelled_identity, candidates.clone()))
        .expect_err("cancelled request must fail");
    assert_eq!(cancelled.code(), AiErrorCode::Cancelled);

    provider
        .infer(&request(next_revision_identity, candidates))
        .expect("a different revision must not be cancelled");
}

#[test]
fn stale_response_identity_does_not_match_current_revision() {
    let candidates = candidates();
    let old_identity = identity(4, 11, 8, &candidates);
    let response = MockProvider::default()
        .infer(&request(old_identity, candidates.clone()))
        .expect("mock response");
    let current_identity = identity(4, 12, 9, &candidates);

    assert!(!response.matches(current_identity));
    assert!(!response.identity().matches_current(
        current_identity.session_id(),
        current_identity.composition_revision(),
        current_identity.candidate_set_hash(),
    ));
}

#[test]
fn expired_deadline_fails_without_waiting() {
    let candidates = candidates();
    let identity = identity(8, 1, 1, &candidates);
    let budget = AiBudget::for_feature(AiFeature::CandidateRerank);
    let issued_at = Instant::now() - Duration::from_millis(100);
    let error = AiRequestBuilder::new_at(
        identity,
        AiFeature::CandidateRerank,
        "zh-Hans",
        HardwareTier::Tier1,
        budget,
        issued_at,
    )
    .with_base_candidates(candidates)
    .build(&PrivacyGuard, AiFeaturePolicy::local_rules_enabled(true))
    .expect_err("expired request must time out");
    assert_eq!(error.code(), AiErrorCode::Timeout);
}

#[test]
fn mismatched_candidate_hash_is_rejected() {
    let candidates = candidates();
    let wrong_identity = AiRequestIdentity::new(
        AiSessionId::from_u128(2),
        AiRequestId::new(3),
        AiCompositionRevision::new(4),
        AiCandidateSetHash::from_ordered_texts(["别的候选"]),
    );

    let error = AiRequestBuilder::new(
        wrong_identity,
        AiFeature::CandidateRerank,
        "zh-Hans",
        HardwareTier::Tier1,
        AiBudget::for_feature(AiFeature::CandidateRerank),
    )
    .with_base_candidates(candidates)
    .build(&PrivacyGuard, AiFeaturePolicy::local_rules_enabled(true))
    .expect_err("candidate identity mismatch must fail");
    assert_eq!(error.code(), AiErrorCode::IdentityMismatch);
}

#[test]
fn request_and_response_debug_output_redacts_text() {
    let candidates = candidates();
    let identity = identity(1, 2, 3, &candidates);
    let request = request(identity, candidates);
    let request_debug = format!("{request:?}");
    assert!(!request_debug.contains("nihao"));
    assert!(!request_debug.contains("你好"));
    assert!(!request_debug.contains("今天"));
    assert!(request_debug.contains("AiSessionId(<opaque>)"));
    assert!(request_debug.contains("AiCandidateSetHash(<redacted>)"));

    let response = MockProvider::default()
        .infer(&request)
        .expect("mock response");
    let response_debug = format!("{response:?}");
    assert!(!response_debug.contains("你好"));
}

#[test]
fn feature_budgets_follow_the_approved_latency_classes() {
    assert_eq!(
        AiBudget::for_feature(AiFeature::CandidateRerank).max_elapsed(),
        Duration::from_millis(30)
    );
    assert_eq!(
        AiBudget::for_feature(AiFeature::ShortCompletion).max_elapsed(),
        Duration::from_millis(800)
    );
    assert_eq!(
        AiBudget::for_feature(AiFeature::RewritePolite).max_elapsed(),
        Duration::from_secs(3)
    );
}
