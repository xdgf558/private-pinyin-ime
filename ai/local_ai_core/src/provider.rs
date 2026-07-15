use crate::{AiError, AiFeature, AiRequest, AiRequestIdentity, AiResponse};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderHealth {
    Available,
    Unavailable,
}

pub trait LocalAiProvider: Send + Sync {
    fn provider_id(&self) -> &'static str;
    fn capabilities(&self) -> &'static [AiFeature];
    fn health(&self) -> ProviderHealth;

    /// Runs one inference request synchronously on the calling thread.
    ///
    /// A deadline is cooperative and does not preempt a blocked caller. Platform hosts
    /// must dispatch this method through a bounded worker queue and must never call it
    /// directly from an IMK main thread, TSF edit-session thread, or iOS UI/input thread.
    fn infer(&self, request: &AiRequest) -> Result<AiResponse, AiError>;
    fn cancel(&self, identity: AiRequestIdentity);
}
