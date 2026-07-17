#![forbid(unsafe_code)]

mod budget;
mod error;
mod feature;
mod hardware;
mod identity;
mod mock_provider;
mod privacy_guard;
mod provider;
mod request;
mod request_builder;
mod response;
mod rules;

pub use budget::{AiBudget, AiDeadline};
pub use error::{AiError, AiErrorCode};
pub use feature::AiFeature;
pub use hardware::HardwareTier;
pub use identity::{
    AiCandidateSetHash, AiCompositionRevision, AiRequestId, AiRequestIdentity, AiSessionId,
};
pub use mock_provider::MockProvider;
pub use privacy_guard::{
    AiFeaturePolicy, AiModelLicenseState, PrivacyGuard, MAX_BASE_CANDIDATES,
    MAX_CANDIDATE_PINYIN_CHARS, MAX_CANDIDATE_TEXT_UNITS, MAX_COMPOSITION_TEXT_UNITS,
    MAX_LOCALE_CHARS, MAX_RAW_PINYIN_CHARS, MAX_RECENT_TOKENS, MAX_RECENT_TOKEN_UNITS,
    MAX_TOTAL_CONTEXT_UNITS,
};
pub use provider::{LocalAiProvider, ProviderHealth};
pub use request::{AiCandidateInput, AiPrivacyMode, AiRawInputKind, AiRequest};
pub use request_builder::AiRequestBuilder;
pub use response::{AiCandidateOutput, AiReasonCode, AiResponse, AiStatus};
pub use rules::{
    EnglishTermPreserver, LexiconCleanupAnalyzer, LexiconCleanupReasonCode,
    LexiconCleanupSuggestion, MixedInputSegment, MixedInputSegmentKind, MixedInputSegmentation,
    PinyinCorrectionReason, PinyinCorrectionSuggestion, PinyinCorrector, UserLexiconSnapshotEntry,
    MAX_CLEANUP_ENTRIES, MAX_CLEANUP_SUGGESTIONS, MAX_MIXED_INPUT_BYTES, MAX_PINYIN_CORRECTIONS,
};

#[cfg(test)]
mod privacy_tests;
#[cfg(test)]
mod tests;
