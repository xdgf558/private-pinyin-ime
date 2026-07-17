use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AiErrorCode {
    Disabled,
    ModelNotFound,
    ProviderUnavailable,
    FeatureUnsupported,
    Timeout,
    Cancelled,
    IdentityMismatch,
    InvalidBudget,
    InputRejectedByPrivacyGuard,
    OutputRejectedBySafetyGuard,
    ModelManifestInvalid,
    ModelIntegrityMismatch,
    ModelPlatformUnsupported,
    ModelLicenseNotApproved,
    HardwareTooLow,
    Internal,
}

impl AiErrorCode {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Disabled => "AI_DISABLED",
            Self::ModelNotFound => "AI_MODEL_NOT_FOUND",
            Self::ProviderUnavailable => "AI_PROVIDER_UNAVAILABLE",
            Self::FeatureUnsupported => "AI_FEATURE_UNSUPPORTED",
            Self::Timeout => "AI_TIMEOUT",
            Self::Cancelled => "AI_CANCELLED",
            Self::IdentityMismatch => "AI_IDENTITY_MISMATCH",
            Self::InvalidBudget => "AI_INVALID_BUDGET",
            Self::InputRejectedByPrivacyGuard => "AI_INPUT_REJECTED_BY_PRIVACY_GUARD",
            Self::OutputRejectedBySafetyGuard => "AI_OUTPUT_REJECTED_BY_SAFETY_GUARD",
            Self::ModelManifestInvalid => "AI_MODEL_MANIFEST_INVALID",
            Self::ModelIntegrityMismatch => "AI_MODEL_INTEGRITY_MISMATCH",
            Self::ModelPlatformUnsupported => "AI_MODEL_PLATFORM_UNSUPPORTED",
            Self::ModelLicenseNotApproved => "AI_MODEL_LICENSE_NOT_APPROVED",
            Self::HardwareTooLow => "AI_HARDWARE_TOO_LOW",
            Self::Internal => "AI_INTERNAL_ERROR",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AiError {
    code: AiErrorCode,
}

impl AiError {
    pub const fn new(code: AiErrorCode) -> Self {
        Self { code }
    }

    pub const fn code(self) -> AiErrorCode {
        self.code
    }
}

impl fmt::Display for AiError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.code.as_str())
    }
}

impl std::error::Error for AiError {}
