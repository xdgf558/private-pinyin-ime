use std::fmt;
use std::time::Instant;

use crate::{
    AiBudget, AiCandidateInput, AiError, AiFeature, AiFeaturePolicy, AiPrivacyMode, AiRawInputKind,
    AiRequest, AiRequestIdentity, HardwareTier, PrivacyGuard,
};

pub struct AiRequestBuilder {
    identity: AiRequestIdentity,
    feature: AiFeature,
    locale: String,
    raw_input_kind: AiRawInputKind,
    raw_pinyin: Option<String>,
    composition_text: Option<String>,
    base_candidates: Vec<AiCandidateInput>,
    recent_tokens: Vec<String>,
    user_action_required: bool,
    privacy_mode: AiPrivacyMode,
    hardware_tier: HardwareTier,
    budget: AiBudget,
    issued_at: Instant,
    secure_input: bool,
}

impl AiRequestBuilder {
    pub fn new(
        identity: AiRequestIdentity,
        feature: AiFeature,
        locale: impl Into<String>,
        hardware_tier: HardwareTier,
        budget: AiBudget,
    ) -> Self {
        Self::new_at(
            identity,
            feature,
            locale,
            hardware_tier,
            budget,
            Instant::now(),
        )
    }

    pub fn new_at(
        identity: AiRequestIdentity,
        feature: AiFeature,
        locale: impl Into<String>,
        hardware_tier: HardwareTier,
        budget: AiBudget,
        issued_at: Instant,
    ) -> Self {
        Self {
            identity,
            feature,
            locale: locale.into(),
            raw_input_kind: AiRawInputKind::FullPinyin,
            raw_pinyin: None,
            composition_text: None,
            base_candidates: Vec::new(),
            recent_tokens: Vec::new(),
            user_action_required: false,
            privacy_mode: AiPrivacyMode::Standard,
            hardware_tier,
            budget,
            issued_at,
            secure_input: false,
        }
    }

    pub fn with_raw_pinyin(mut self, raw_pinyin: impl Into<String>) -> Self {
        self.raw_pinyin = Some(raw_pinyin.into());
        self
    }

    pub const fn with_raw_input_kind(mut self, raw_input_kind: AiRawInputKind) -> Self {
        self.raw_input_kind = raw_input_kind;
        self
    }

    pub fn with_composition_text(mut self, composition_text: impl Into<String>) -> Self {
        self.composition_text = Some(composition_text.into());
        self
    }

    pub fn with_base_candidates(mut self, candidates: Vec<AiCandidateInput>) -> Self {
        self.base_candidates = candidates;
        self
    }

    pub fn with_recent_tokens(mut self, tokens: Vec<String>) -> Self {
        self.recent_tokens = tokens;
        self
    }

    pub const fn requiring_user_action(mut self, required: bool) -> Self {
        self.user_action_required = required;
        self
    }

    pub const fn with_privacy_mode(mut self, privacy_mode: AiPrivacyMode) -> Self {
        self.privacy_mode = privacy_mode;
        self
    }

    pub const fn with_secure_input(mut self, secure_input: bool) -> Self {
        self.secure_input = secure_input;
        self
    }

    pub fn build(
        self,
        guard: &PrivacyGuard,
        policy: AiFeaturePolicy,
    ) -> Result<AiRequest, AiError> {
        let recent_tokens = guard.minimize_recent_tokens(self.recent_tokens);
        let mut request = AiRequest::new_at(
            self.identity,
            self.feature,
            self.locale,
            self.hardware_tier,
            self.budget,
            self.issued_at,
        )
        .with_raw_input_kind(self.raw_input_kind)
        .with_base_candidates(self.base_candidates)
        .with_recent_tokens(recent_tokens)
        .requiring_user_action(self.user_action_required)
        .with_privacy_mode(self.privacy_mode)
        .with_secure_input(self.secure_input);

        if let Some(raw_pinyin) = self.raw_pinyin {
            request = request.with_raw_pinyin(raw_pinyin);
        }
        if let Some(composition_text) = self.composition_text {
            request = request.with_composition_text(composition_text);
        }

        guard.validate(&request, policy)?;
        Ok(request)
    }
}

impl fmt::Debug for AiRequestBuilder {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AiRequestBuilder")
            .field("identity", &self.identity)
            .field("feature", &self.feature)
            .field("locale", &"<redacted>")
            .field("raw_input_kind", &self.raw_input_kind)
            .field("has_raw_pinyin", &self.raw_pinyin.is_some())
            .field("has_composition_text", &self.composition_text.is_some())
            .field("base_candidate_count", &self.base_candidates.len())
            .field("recent_token_count", &self.recent_tokens.len())
            .field("user_action_required", &self.user_action_required)
            .field("privacy_mode", &self.privacy_mode)
            .field("hardware_tier", &self.hardware_tier)
            .field("budget", &self.budget)
            .field("secure_input", &self.secure_input)
            .finish()
    }
}
