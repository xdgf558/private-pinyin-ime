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
    fn infer(&self, request: &AiRequest) -> Result<AiResponse, AiError>;
    fn cancel(&self, identity: AiRequestIdentity);
}
