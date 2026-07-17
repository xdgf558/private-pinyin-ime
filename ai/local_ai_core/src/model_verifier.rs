use std::collections::HashSet;
use std::fmt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::model_integrity::{
    canonical_package_root, read_verified_package_artifact, verify_package_artifact,
};
use crate::{
    AiError, AiErrorCode, HardwareProfile, ModelArtifactKind, ModelManifest, ModelPlatform,
};

pub const MODEL_APPROVAL_REGISTRY_SCHEMA_VERSION: u32 = 1;
const EMBEDDED_APPROVAL_REGISTRY_JSON: &str = include_str!("../../models/approved_models.json");

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ModelApprovalEntry {
    approval_id: String,
    model_id: String,
    version: String,
    manifest_fingerprint_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ModelApprovalRegistry {
    schema_version: u32,
    approvals: Vec<ModelApprovalEntry>,
}

impl ModelApprovalRegistry {
    pub(crate) fn embedded() -> Result<Self, AiError> {
        Self::from_json(EMBEDDED_APPROVAL_REGISTRY_JSON)
    }

    pub(crate) fn from_json(json: &str) -> Result<Self, AiError> {
        let registry = serde_json::from_str::<Self>(json)
            .map_err(|_| AiError::new(AiErrorCode::ModelManifestInvalid))?;
        registry.validate()?;
        Ok(registry)
    }

    #[cfg(test)]
    pub(crate) fn approval_count(&self) -> usize {
        self.approvals.len()
    }

    fn approves(&self, manifest: &ModelManifest) -> Result<bool, AiError> {
        let fingerprint = manifest.approval_fingerprint()?;
        Ok(self.approvals.iter().any(|approval| {
            approval.model_id == manifest.id()
                && approval.version == manifest.version()
                && approval.manifest_fingerprint_sha256 == fingerprint
        }))
    }

    fn validate(&self) -> Result<(), AiError> {
        if self.schema_version != MODEL_APPROVAL_REGISTRY_SCHEMA_VERSION {
            return Err(manifest_invalid());
        }
        let mut approval_ids = HashSet::new();
        let mut model_versions = HashSet::new();
        for approval in &self.approvals {
            if !is_safe_approval_id(&approval.approval_id)
                || approval.model_id.is_empty()
                || approval.version.is_empty()
                || !is_lower_sha256(&approval.manifest_fingerprint_sha256)
                || !approval_ids.insert(approval.approval_id.as_str())
                || !model_versions.insert((approval.model_id.as_str(), approval.version.as_str()))
            {
                return Err(manifest_invalid());
            }
        }
        Ok(())
    }
}

pub struct ModelPackageVerifier {
    approval_registry: ModelApprovalRegistry,
    platform: ModelPlatform,
    hardware: HardwareProfile,
}

impl ModelPackageVerifier {
    pub fn new(platform: ModelPlatform, hardware: HardwareProfile) -> Result<Self, AiError> {
        Ok(Self {
            approval_registry: ModelApprovalRegistry::embedded()?,
            platform,
            hardware,
        })
    }

    #[cfg(test)]
    pub(crate) const fn new_with_registry(
        approval_registry: ModelApprovalRegistry,
        platform: ModelPlatform,
        hardware: HardwareProfile,
    ) -> Self {
        Self {
            approval_registry,
            platform,
            hardware,
        }
    }

    pub fn verify(
        &self,
        package_root: &Path,
        manifest: &ModelManifest,
    ) -> Result<VerifiedModelPackage, AiError> {
        manifest.validate_final()?;
        if !manifest.license().redistribution_allowed()
            || !manifest.license().owner_approved()
            || !self.approval_registry.approves(manifest)?
        {
            return Err(AiError::new(AiErrorCode::ModelLicenseNotApproved));
        }
        if !manifest.platforms().contains(&self.platform) {
            return Err(AiError::new(AiErrorCode::ModelPlatformUnsupported));
        }
        if !self.hardware.supports_model(manifest.hardware())
            || manifest
                .capabilities()
                .iter()
                .any(|feature| !self.hardware.tier().supports(*feature))
        {
            return Err(AiError::new(AiErrorCode::HardwareTooLow));
        }

        for artifact in manifest.artifacts() {
            verify_package_artifact(
                package_root,
                artifact.path(),
                artifact.sha256(),
                artifact.size_bytes(),
            )?;
        }

        Ok(VerifiedModelPackage {
            package_root: canonical_package_root(package_root)?,
            manifest: manifest.clone(),
        })
    }
}

pub struct VerifiedModelPackage {
    package_root: PathBuf,
    manifest: ModelManifest,
}

impl VerifiedModelPackage {
    pub fn manifest(&self) -> &ModelManifest {
        &self.manifest
    }

    pub fn artifact_count(&self) -> usize {
        self.manifest.artifacts().len()
    }

    pub fn read_primary_model_bytes(&self, maximum_size_bytes: u64) -> Result<Vec<u8>, AiError> {
        let artifact = self
            .manifest
            .artifacts()
            .iter()
            .find(|artifact| artifact.kind() == ModelArtifactKind::Model)
            .ok_or_else(manifest_invalid)?;
        read_verified_package_artifact(
            &self.package_root,
            artifact.path(),
            artifact.sha256(),
            artifact.size_bytes(),
            maximum_size_bytes,
        )
    }
}

impl fmt::Debug for VerifiedModelPackage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("VerifiedModelPackage")
            .field("model_id", &self.manifest.id())
            .field("version", &self.manifest.version())
            .field("artifact_count", &self.artifact_count())
            .field("package_root", &"<redacted>")
            .finish()
    }
}

fn is_safe_approval_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 96
        && value.is_ascii()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

fn is_lower_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn manifest_invalid() -> AiError {
    AiError::new(AiErrorCode::ModelManifestInvalid)
}
