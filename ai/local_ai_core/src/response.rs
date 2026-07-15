use std::fmt;
use std::time::Duration;

use crate::{AiFeature, AiRequestIdentity};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AiStatus {
    Completed,
    NoSuggestion,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AiReasonCode {
    MockDeterministic,
}

#[derive(Clone, PartialEq, Eq)]
pub struct AiCandidateOutput {
    text: String,
    base_index: Option<usize>,
    score_delta_milli: i32,
    reason_code: AiReasonCode,
}

impl AiCandidateOutput {
    pub fn new(
        text: impl Into<String>,
        base_index: Option<usize>,
        score_delta_milli: i32,
        reason_code: AiReasonCode,
    ) -> Self {
        Self {
            text: text.into(),
            base_index,
            score_delta_milli,
            reason_code,
        }
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    pub const fn base_index(&self) -> Option<usize> {
        self.base_index
    }

    pub const fn score_delta_milli(&self) -> i32 {
        self.score_delta_milli
    }

    pub const fn reason_code(&self) -> AiReasonCode {
        self.reason_code
    }
}

impl fmt::Debug for AiCandidateOutput {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AiCandidateOutput")
            .field("text", &"<redacted>")
            .field("base_index", &self.base_index)
            .field("score_delta_milli", &self.score_delta_milli)
            .field("reason_code", &self.reason_code)
            .finish()
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct AiResponse {
    identity: AiRequestIdentity,
    feature: AiFeature,
    status: AiStatus,
    candidates: Vec<AiCandidateOutput>,
    elapsed: Duration,
    provider_id: &'static str,
}

impl AiResponse {
    pub(crate) fn new(
        identity: AiRequestIdentity,
        feature: AiFeature,
        status: AiStatus,
        candidates: Vec<AiCandidateOutput>,
        elapsed: Duration,
        provider_id: &'static str,
    ) -> Self {
        Self {
            identity,
            feature,
            status,
            candidates,
            elapsed,
            provider_id,
        }
    }

    pub const fn identity(&self) -> AiRequestIdentity {
        self.identity
    }

    pub const fn feature(&self) -> AiFeature {
        self.feature
    }

    pub const fn status(&self) -> AiStatus {
        self.status
    }

    pub fn candidates(&self) -> &[AiCandidateOutput] {
        &self.candidates
    }

    pub const fn elapsed(&self) -> Duration {
        self.elapsed
    }

    pub const fn provider_id(&self) -> &'static str {
        self.provider_id
    }

    pub fn matches(&self, identity: AiRequestIdentity) -> bool {
        self.identity == identity
    }
}

impl fmt::Debug for AiResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AiResponse")
            .field("identity", &self.identity)
            .field("feature", &self.feature)
            .field("status", &self.status)
            .field("candidate_count", &self.candidates.len())
            .field("elapsed", &self.elapsed)
            .field("provider_id", &self.provider_id)
            .finish()
    }
}
