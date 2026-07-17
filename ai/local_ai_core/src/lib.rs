#![forbid(unsafe_code)]

mod budget;
mod error;
mod feature;
mod hardware;
mod identity;
mod lite_ranker;
mod mock_provider;
mod model_integrity;
mod model_manifest;
mod model_verifier;
mod privacy_guard;
mod provider;
mod request;
mod request_builder;
mod response;
mod rules;

pub use budget::{AiBudget, AiDeadline};
pub use error::{AiError, AiErrorCode};
pub use feature::AiFeature;
pub use hardware::{HardwareProfile, HardwareTier, ModelHardwareRequirements};
pub use identity::{
    AiCandidateSetHash, AiCompositionRevision, AiRequestId, AiRequestIdentity, AiSessionId,
};
pub use lite_ranker::{
    AiLiteRanker, AI_LITE_FEATURE_SCALE, AI_LITE_FEATURE_SCHEMA_VERSION,
    AI_LITE_MODEL_SCHEMA_VERSION, AI_LITE_RANKER_VERSION, MAX_AI_LITE_RANKER_MODEL_BYTES,
};
pub use mock_provider::MockProvider;
pub use model_manifest::{
    ModelArtifact, ModelArtifactKind, ModelClass, ModelLicense, ModelManifest, ModelPlatform,
    ModelPrivacyDeclaration, ModelRuntime, MAX_AI_LITE_PACKAGE_BYTES, MAX_MODEL_ARTIFACTS,
    MAX_WRITER_PACKAGE_BYTES, MODEL_MANIFEST_SCHEMA_VERSION,
};
pub use model_verifier::{
    ModelPackageVerifier, VerifiedModelPackage, MODEL_APPROVAL_REGISTRY_SCHEMA_VERSION,
};
pub use privacy_guard::{
    AiFeaturePolicy, AiModelLicenseState, PrivacyGuard, MAX_BASE_CANDIDATES,
    MAX_CANDIDATE_PINYIN_CHARS, MAX_CANDIDATE_TEXT_UNITS, MAX_COMPOSITION_TEXT_UNITS,
    MAX_LOCALE_CHARS, MAX_RAW_PINYIN_CHARS, MAX_RECENT_TOKENS, MAX_RECENT_TOKEN_UNITS,
    MAX_TOTAL_CONTEXT_UNITS,
};
pub use provider::{LocalAiProvider, ProviderHealth};
pub use request::{
    AiCandidateInput, AiLiteCandidateFeatures, AiPrivacyMode, AiRawInputKind, AiRequest,
};
pub use request_builder::AiRequestBuilder;
pub use response::{AiCandidateOutput, AiReasonCode, AiResponse, AiStatus};
pub use rules::{
    EnglishTermPreserver, LexiconCleanupAnalyzer, LexiconCleanupReasonCode,
    LexiconCleanupSuggestion, MixedInputSegment, MixedInputSegmentKind, MixedInputSegmentation,
    PinyinCorrectionReason, PinyinCorrectionSuggestion, PinyinCorrector, UserLexiconSnapshotEntry,
    MAX_CLEANUP_ENTRIES, MAX_CLEANUP_SUGGESTIONS, MAX_MIXED_INPUT_BYTES, MAX_PINYIN_CORRECTIONS,
};

#[cfg(test)]
mod model_tests;
#[cfg(test)]
mod privacy_tests;
#[cfg(test)]
mod tests;
