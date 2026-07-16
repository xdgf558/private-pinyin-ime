use std::fmt;
use std::time::Instant;

use crate::{AiBudget, AiCandidateSetHash, AiDeadline, AiFeature, AiRequestIdentity, HardwareTier};

#[derive(Clone, PartialEq, Eq)]
pub struct AiCandidateInput {
    text: String,
    pinyin: Option<String>,
    base_rank: usize,
    base_score: i64,
}

impl AiCandidateInput {
    pub fn new(text: impl Into<String>, base_rank: usize) -> Self {
        Self {
            text: text.into(),
            pinyin: None,
            base_rank,
            base_score: 0,
        }
    }

    pub fn with_pinyin(mut self, pinyin: impl Into<String>) -> Self {
        self.pinyin = Some(pinyin.into());
        self
    }

    pub const fn with_base_score(mut self, base_score: i64) -> Self {
        self.base_score = base_score;
        self
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    pub fn pinyin(&self) -> Option<&str> {
        self.pinyin.as_deref()
    }

    pub const fn base_rank(&self) -> usize {
        self.base_rank
    }

    pub const fn base_score(&self) -> i64 {
        self.base_score
    }
}

impl fmt::Debug for AiCandidateInput {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AiCandidateInput")
            .field("text", &"<redacted>")
            .field("has_pinyin", &self.pinyin.is_some())
            .field("base_rank", &self.base_rank)
            .field("base_score", &self.base_score)
            .finish()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AiPrivacyMode {
    Standard,
    Strict,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AiRawInputKind {
    FullPinyin,
    NineKeyDigits,
}

#[derive(Clone, PartialEq, Eq)]
pub struct AiRequest {
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
    deadline: AiDeadline,
    secure_input: bool,
}

impl AiRequest {
    pub(crate) fn new_at(
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
            deadline: AiDeadline::from_start(issued_at, budget.max_elapsed()),
            secure_input: false,
        }
    }

    pub(crate) fn with_raw_pinyin(mut self, raw_pinyin: impl Into<String>) -> Self {
        self.raw_pinyin = Some(raw_pinyin.into());
        self
    }

    pub(crate) const fn with_raw_input_kind(mut self, raw_input_kind: AiRawInputKind) -> Self {
        self.raw_input_kind = raw_input_kind;
        self
    }

    pub(crate) fn with_composition_text(mut self, composition_text: impl Into<String>) -> Self {
        self.composition_text = Some(composition_text.into());
        self
    }

    pub(crate) fn with_base_candidates(mut self, candidates: Vec<AiCandidateInput>) -> Self {
        self.base_candidates = candidates;
        self
    }

    pub(crate) fn with_recent_tokens(mut self, tokens: Vec<String>) -> Self {
        self.recent_tokens = tokens;
        self
    }

    pub(crate) const fn requiring_user_action(mut self, required: bool) -> Self {
        self.user_action_required = required;
        self
    }

    pub(crate) const fn with_privacy_mode(mut self, privacy_mode: AiPrivacyMode) -> Self {
        self.privacy_mode = privacy_mode;
        self
    }

    pub(crate) const fn with_secure_input(mut self, secure_input: bool) -> Self {
        self.secure_input = secure_input;
        self
    }

    pub const fn identity(&self) -> AiRequestIdentity {
        self.identity
    }

    pub const fn feature(&self) -> AiFeature {
        self.feature
    }

    pub fn locale(&self) -> &str {
        &self.locale
    }

    pub const fn raw_input_kind(&self) -> AiRawInputKind {
        self.raw_input_kind
    }

    pub fn raw_pinyin(&self) -> Option<&str> {
        self.raw_pinyin.as_deref()
    }

    pub fn composition_text(&self) -> Option<&str> {
        self.composition_text.as_deref()
    }

    pub fn base_candidates(&self) -> &[AiCandidateInput] {
        &self.base_candidates
    }

    pub fn recent_tokens(&self) -> &[String] {
        &self.recent_tokens
    }

    pub const fn user_action_required(&self) -> bool {
        self.user_action_required
    }

    pub const fn privacy_mode(&self) -> AiPrivacyMode {
        self.privacy_mode
    }

    pub const fn hardware_tier(&self) -> HardwareTier {
        self.hardware_tier
    }

    pub const fn budget(&self) -> AiBudget {
        self.budget
    }

    pub const fn deadline(&self) -> AiDeadline {
        self.deadline
    }

    pub const fn secure_input(&self) -> bool {
        self.secure_input
    }

    pub fn computed_candidate_set_hash(&self) -> AiCandidateSetHash {
        AiCandidateSetHash::from_ordered_texts(
            self.base_candidates.iter().map(AiCandidateInput::text),
        )
    }

    pub fn has_consistent_candidate_identity(&self) -> bool {
        self.identity.candidate_set_hash() == self.computed_candidate_set_hash()
    }
}

impl fmt::Debug for AiRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AiRequest")
            .field("identity", &self.identity)
            .field("feature", &self.feature)
            .field("locale", &self.locale)
            .field("raw_input_kind", &self.raw_input_kind)
            .field("has_raw_pinyin", &self.raw_pinyin.is_some())
            .field("has_composition_text", &self.composition_text.is_some())
            .field("base_candidate_count", &self.base_candidates.len())
            .field("recent_token_count", &self.recent_tokens.len())
            .field("user_action_required", &self.user_action_required)
            .field("privacy_mode", &self.privacy_mode)
            .field("hardware_tier", &self.hardware_tier)
            .field("budget", &self.budget)
            .field("deadline", &self.deadline)
            .field("secure_input", &self.secure_input)
            .finish()
    }
}
