use std::collections::HashSet;
use std::sync::Mutex;
use std::time::Duration;

use crate::{
    AiCandidateOutput, AiError, AiErrorCode, AiFeature, AiReasonCode, AiRequest, AiRequestIdentity,
    AiResponse, AiStatus, LocalAiProvider, ProviderHealth,
};

pub struct MockProvider {
    available: bool,
    cancelled: Mutex<HashSet<AiRequestIdentity>>,
}

impl MockProvider {
    pub fn available() -> Self {
        Self {
            available: true,
            cancelled: Mutex::new(HashSet::new()),
        }
    }

    pub fn unavailable() -> Self {
        Self {
            available: false,
            cancelled: Mutex::new(HashSet::new()),
        }
    }

    fn is_cancelled(&self, identity: AiRequestIdentity) -> Result<bool, AiError> {
        self.cancelled
            .lock()
            .map(|identities| identities.contains(&identity))
            .map_err(|_| AiError::new(AiErrorCode::Internal))
    }
}

impl Default for MockProvider {
    fn default() -> Self {
        Self::available()
    }
}

impl LocalAiProvider for MockProvider {
    fn provider_id(&self) -> &'static str {
        "private-pinyin-mock-v1"
    }

    fn capabilities(&self) -> &'static [AiFeature] {
        &AiFeature::ALL
    }

    fn health(&self) -> ProviderHealth {
        if self.available {
            ProviderHealth::Available
        } else {
            ProviderHealth::Unavailable
        }
    }

    fn infer(&self, request: &AiRequest) -> Result<AiResponse, AiError> {
        if !self.available {
            return Err(AiError::new(AiErrorCode::ProviderUnavailable));
        }
        if !self.capabilities().contains(&request.feature()) {
            return Err(AiError::new(AiErrorCode::FeatureUnsupported));
        }
        if !request.budget().is_valid() {
            return Err(AiError::new(AiErrorCode::InvalidBudget));
        }
        if request.deadline().is_expired() {
            return Err(AiError::new(AiErrorCode::Timeout));
        }
        if !request.has_consistent_candidate_identity() {
            return Err(AiError::new(AiErrorCode::IdentityMismatch));
        }
        if self.is_cancelled(request.identity())? {
            return Err(AiError::new(AiErrorCode::Cancelled));
        }
        if !request.hardware_tier().supports(request.feature()) {
            return Err(AiError::new(AiErrorCode::HardwareTooLow));
        }

        let output_limit = request
            .budget()
            .max_candidates()
            .min(request.budget().max_suggestions());
        let candidates = request
            .base_candidates()
            .iter()
            .take(output_limit)
            .enumerate()
            .map(|(index, candidate)| {
                AiCandidateOutput::new(
                    candidate.text(),
                    Some(index),
                    0,
                    AiReasonCode::MockDeterministic,
                )
            })
            .collect::<Vec<_>>();
        let status = if candidates.is_empty() {
            AiStatus::NoSuggestion
        } else {
            AiStatus::Completed
        };

        Ok(AiResponse::new(
            request.identity(),
            request.feature(),
            status,
            candidates,
            Duration::ZERO,
            self.provider_id(),
        ))
    }

    fn cancel(&self, identity: AiRequestIdentity) {
        if let Ok(mut identities) = self.cancelled.lock() {
            identities.insert(identity);
        }
    }
}
