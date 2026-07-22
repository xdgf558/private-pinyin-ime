use std::time::Duration;

use serde::Deserialize;

use crate::{
    AiBudget, AiCandidateInput, AiCandidateSetHash, AiCompositionRevision, AiErrorCode, AiFeature,
    AiFeaturePolicy, AiModelLicenseState, AiPrivacyMode, AiRawInputKind, AiRequestBuilder,
    AiRequestId, AiRequestIdentity, AiSessionId, HardwareTier, PrivacyGuard, MAX_RECENT_TOKENS,
};

fn candidates() -> Vec<AiCandidateInput> {
    vec![
        AiCandidateInput::new("你好", 0).with_pinyin("ni hao"),
        AiCandidateInput::new("你号", 1).with_pinyin("ni hao"),
    ]
}

fn identity(candidates: &[AiCandidateInput]) -> AiRequestIdentity {
    AiRequestIdentity::new(
        AiSessionId::from_u128(31),
        AiRequestId::new(7),
        AiCompositionRevision::new(4),
        AiCandidateSetHash::from_ordered_texts(candidates.iter().map(AiCandidateInput::text)),
    )
}

fn builder(feature: AiFeature, hardware_tier: HardwareTier) -> AiRequestBuilder {
    let candidates = candidates();
    AiRequestBuilder::new(
        identity(&candidates),
        feature,
        "zh-Hans",
        hardware_tier,
        AiBudget::for_feature(feature),
    )
    .with_base_candidates(candidates)
}

fn enabled_policy() -> AiFeaturePolicy {
    AiFeaturePolicy::local_rules_enabled(true)
}

#[derive(Deserialize)]
struct PrivacyCaseSet {
    category: String,
    cases: Vec<String>,
}

fn privacy_cases(contents: &str) -> PrivacyCaseSet {
    serde_json::from_str(contents).expect("valid privacy regression fixture")
}

#[test]
fn normal_request_passes_and_keeps_only_the_last_eight_context_tokens() {
    let tokens = (0..12).map(|index| format!("词{index}")).collect();
    let request = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_raw_pinyin("nihao")
        .with_composition_text("你好")
        .with_recent_tokens(tokens)
        .build(&PrivacyGuard, enabled_policy())
        .expect("normal request must pass");

    assert_eq!(request.recent_tokens().len(), MAX_RECENT_TOKENS);
    assert_eq!(
        request.recent_tokens().first().map(String::as_str),
        Some("词4")
    );
    assert_eq!(
        request.recent_tokens().last().map(String::as_str),
        Some("词11")
    );
}

#[test]
fn secure_input_is_rejected_with_a_code_only_error() {
    let error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_raw_pinyin("nihao")
        .with_secure_input(true)
        .build(&PrivacyGuard, enabled_policy())
        .expect_err("secure input must be rejected");

    assert_eq!(error.code(), AiErrorCode::InputRejectedByPrivacyGuard);
    assert_eq!(error.to_string(), "AI_INPUT_REJECTED_BY_PRIVACY_GUARD");
    assert_eq!(
        format!("{error:?}"),
        "AiError { code: InputRejectedByPrivacyGuard }"
    );
}

#[test]
fn password_and_one_time_code_samples_are_rejected() {
    let fixture = privacy_cases(include_str!("../../eval/privacy_cases/password.json"));
    assert_eq!(fixture.category, "password");
    for sensitive_text in fixture
        .cases
        .into_iter()
        .chain(["验证码 123456".to_owned(), "123456".to_owned()])
    {
        let error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
            .with_composition_text(sensitive_text)
            .build(&PrivacyGuard, enabled_policy())
            .expect_err("sensitive input must be rejected");
        assert_eq!(error.code(), AiErrorCode::InputRejectedByPrivacyGuard);
    }

    let recent_token_error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_recent_tokens(vec!["123456".to_owned()])
        .build(&PrivacyGuard, enabled_policy())
        .expect_err("one-time codes in recent context must be rejected");
    assert_eq!(
        recent_token_error.code(),
        AiErrorCode::InputRejectedByPrivacyGuard
    );

    let sensitive_candidates =
        vec![AiCandidateInput::new("123456", 0).with_pinyin("api_key: live-secret")];
    let candidate_error = AiRequestBuilder::new(
        identity(&sensitive_candidates),
        AiFeature::CandidateRerank,
        "zh-Hans",
        HardwareTier::Tier1,
        AiBudget::for_feature(AiFeature::CandidateRerank),
    )
    .with_base_candidates(sensitive_candidates)
    .build(&PrivacyGuard, enabled_policy())
    .expect_err("sensitive candidate fields must be rejected");
    assert_eq!(
        candidate_error.code(),
        AiErrorCode::InputRejectedByPrivacyGuard
    );
}

#[test]
fn numeric_full_pinyin_is_rejected_without_blocking_declared_nine_key_input() {
    let full_pinyin_error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_raw_pinyin("123456")
        .build(&PrivacyGuard, enabled_policy())
        .expect_err("numeric full-pinyin input must fail closed");
    assert_eq!(
        full_pinyin_error.code(),
        AiErrorCode::InputRejectedByPrivacyGuard
    );

    builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_raw_input_kind(AiRawInputKind::NineKeyDigits)
        .with_raw_pinyin("64426")
        .build(&PrivacyGuard, enabled_policy())
        .expect("declared nine-key input relies on the host secure-input signal");
}

#[test]
fn payment_identity_and_phone_numbers_are_rejected() {
    for (category, contents) in [
        (
            "payment",
            include_str!("../../eval/privacy_cases/payment.json"),
        ),
        (
            "id_card",
            include_str!("../../eval/privacy_cases/id_card.json"),
        ),
        ("phone", include_str!("../../eval/privacy_cases/phone.json")),
    ] {
        let fixture = privacy_cases(contents);
        assert_eq!(fixture.category, category);
        for sensitive_text in fixture.cases {
            let error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
                .with_composition_text(sensitive_text)
                .build(&PrivacyGuard, enabled_policy())
                .expect_err("sensitive number must be rejected");
            assert_eq!(error.code(), AiErrorCode::InputRejectedByPrivacyGuard);
        }
    }
}

#[test]
fn ordinary_security_terms_are_not_treated_as_secret_assignments() {
    let false_positives =
        privacy_cases(include_str!("../../eval/privacy_cases/false_positive.json"));
    assert_eq!(false_positives.category, "false_positive");
    for ordinary_text in false_positives.cases {
        builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
            .with_composition_text(ordinary_text)
            .build(&PrivacyGuard, enabled_policy())
            .expect("ordinary security terminology must remain usable");
    }

    let error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_composition_text("api key: secret-value")
        .build(&PrivacyGuard, enabled_policy())
        .expect_err("assigned secret must be rejected");
    assert_eq!(error.code(), AiErrorCode::InputRejectedByPrivacyGuard);
}

#[test]
fn token_assignment_fixture_is_rejected_without_logging_content() {
    let fixture = privacy_cases(include_str!("../../eval/privacy_cases/token.json"));
    assert_eq!(fixture.category, "token");
    for sensitive_text in fixture.cases {
        let error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
            .with_composition_text(sensitive_text)
            .build(&PrivacyGuard, enabled_policy())
            .expect_err("assigned token must be rejected");
        assert_eq!(error.code(), AiErrorCode::InputRejectedByPrivacyGuard);
        assert_eq!(error.to_string(), "AI_INPUT_REJECTED_BY_PRIVACY_GUARD");
    }
}

#[test]
fn oversized_raw_pinyin_and_composition_are_rejected() {
    let raw_error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_raw_pinyin("a".repeat(65))
        .build(&PrivacyGuard, enabled_policy())
        .expect_err("oversized raw pinyin must fail");
    assert_eq!(raw_error.code(), AiErrorCode::InputRejectedByPrivacyGuard);

    let composition_error = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_composition_text("猫".repeat(301))
        .build(&PrivacyGuard, enabled_policy())
        .expect_err("oversized composition must fail");
    assert_eq!(
        composition_error.code(),
        AiErrorCode::InputRejectedByPrivacyGuard
    );
}

#[test]
fn feature_policy_hardware_and_budget_fail_closed() {
    let disabled = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .build(&PrivacyGuard, AiFeaturePolicy::disabled())
        .expect_err("disabled feature must fail");
    assert_eq!(disabled.code(), AiErrorCode::Disabled);

    let unapproved = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .build(
            &PrivacyGuard,
            AiFeaturePolicy::new(true, true, AiModelLicenseState::NotApproved),
        )
        .expect_err("unapproved model must fail");
    assert_eq!(unapproved.code(), AiErrorCode::ModelLicenseNotApproved);

    let low_hardware = builder(AiFeature::CandidateRerank, HardwareTier::Tier0)
        .build(&PrivacyGuard, enabled_policy())
        .expect_err("unsupported hardware must fail");
    assert_eq!(low_hardware.code(), AiErrorCode::HardwareTooLow);

    let candidates = candidates();
    let oversized_budget = AiRequestBuilder::new(
        identity(&candidates),
        AiFeature::CandidateRerank,
        "zh-Hans",
        HardwareTier::Tier1,
        AiBudget::new(Duration::from_millis(31), 32, 3),
    )
    .with_base_candidates(candidates)
    .build(&PrivacyGuard, enabled_policy())
    .expect_err("expanded budget must fail");
    assert_eq!(oversized_budget.code(), AiErrorCode::InvalidBudget);
}

#[test]
fn strict_privacy_and_explicit_user_action_are_enforced() {
    let strict_disabled = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_privacy_mode(AiPrivacyMode::Strict)
        .build(&PrivacyGuard, AiFeaturePolicy::local_rules_enabled(false))
        .expect_err("policy can disable all AI in strict privacy mode");
    assert_eq!(strict_disabled.code(), AiErrorCode::Disabled);

    builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_privacy_mode(AiPrivacyMode::Strict)
        .build(&PrivacyGuard, enabled_policy())
        .expect("AI Lite may be explicitly allowed in strict privacy mode");

    let candidates = candidates();
    let rewrite_builder = || {
        AiRequestBuilder::new(
            identity(&candidates),
            AiFeature::RewritePolite,
            "zh-Hans",
            HardwareTier::Tier2,
            AiBudget::for_feature(AiFeature::RewritePolite),
        )
        .with_base_candidates(candidates.clone())
        .with_composition_text("请尽快处理这个问题")
    };

    let implicit = rewrite_builder()
        .build(&PrivacyGuard, enabled_policy())
        .expect_err("rewrite must require an explicit action");
    assert_eq!(implicit.code(), AiErrorCode::InputRejectedByPrivacyGuard);

    rewrite_builder()
        .requiring_user_action(true)
        .build(&PrivacyGuard, enabled_policy())
        .expect("explicit rewrite request must pass");
}

#[test]
fn request_builder_debug_output_never_contains_content() {
    let builder = builder(AiFeature::CandidateRerank, HardwareTier::Tier1)
        .with_raw_pinyin("secret-pinyin")
        .with_composition_text("secret composition")
        .with_recent_tokens(vec!["secret context".to_owned()]);
    let debug = format!("{builder:?}");

    assert!(!debug.contains("secret-pinyin"));
    assert!(!debug.contains("secret composition"));
    assert!(!debug.contains("secret context"));
    assert!(debug.contains("has_raw_pinyin: true"));

    let locale_debug = format!(
        "{:?}",
        AiRequestBuilder::new(
            AiRequestIdentity::new(
                AiSessionId::from_u128(1),
                AiRequestId::new(1),
                AiCompositionRevision::new(1),
                AiCandidateSetHash::from_ordered_texts(std::iter::empty::<&str>()),
            ),
            AiFeature::CandidateRerank,
            "locale-secret",
            HardwareTier::Tier1,
            AiBudget::for_feature(AiFeature::CandidateRerank),
        )
    );
    assert!(!locale_debug.contains("locale-secret"));
}
