#![forbid(unsafe_code)]

mod budget;
mod error;
mod feature;
mod hardware;
mod identity;
mod mock_provider;
mod provider;
mod request;
mod response;

pub use budget::{AiBudget, AiDeadline};
pub use error::{AiError, AiErrorCode};
pub use feature::AiFeature;
pub use hardware::HardwareTier;
pub use identity::{
    AiCandidateSetHash, AiCompositionRevision, AiRequestId, AiRequestIdentity, AiSessionId,
};
pub use mock_provider::MockProvider;
pub use provider::{LocalAiProvider, ProviderHealth};
pub use request::{AiCandidateInput, AiPrivacyMode, AiRequest};
pub use response::{AiCandidateOutput, AiReasonCode, AiResponse, AiStatus};

#[cfg(test)]
mod tests;
