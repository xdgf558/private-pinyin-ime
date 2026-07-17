use std::collections::HashSet;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::model_integrity::{digest_package_artifact, is_safe_artifact_path, sha256_bytes};
use crate::{AiError, AiErrorCode, AiFeature, ModelHardwareRequirements};

pub const MODEL_MANIFEST_SCHEMA_VERSION: u32 = 1;
pub const MAX_MODEL_ARTIFACTS: usize = 16;
pub const MAX_AI_LITE_PACKAGE_BYTES: u64 = 64 * 1024 * 1024;
pub const MAX_WRITER_PACKAGE_BYTES: u64 = 4 * 1024 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelClass {
    Lite,
    Writer,
}

impl ModelClass {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Lite => "lite",
            Self::Writer => "writer",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelRuntime {
    RustCompact,
    CoreMl,
    Onnx,
    Gguf,
}

impl ModelRuntime {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::RustCompact => "rust_compact",
            Self::CoreMl => "core_ml",
            Self::Onnx => "onnx",
            Self::Gguf => "gguf",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelPlatform {
    Macos,
    Windows,
    Ios,
}

impl ModelPlatform {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Macos => "macos",
            Self::Windows => "windows",
            Self::Ios => "ios",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelArtifactKind {
    Model,
    Tokenizer,
    LicenseNotice,
    Metadata,
}

impl ModelArtifactKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Model => "model",
            Self::Tokenizer => "tokenizer",
            Self::LicenseNotice => "license_notice",
            Self::Metadata => "metadata",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelArtifact {
    kind: ModelArtifactKind,
    path: String,
    sha256: String,
    size_bytes: u64,
}

impl ModelArtifact {
    pub fn kind(&self) -> ModelArtifactKind {
        self.kind
    }

    pub fn path(&self) -> &str {
        &self.path
    }

    pub fn sha256(&self) -> &str {
        &self.sha256
    }

    pub fn size_bytes(&self) -> u64 {
        self.size_bytes
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelLicense {
    name: String,
    url: String,
    source_url: String,
    notice_path: String,
    redistribution_allowed: bool,
    owner_approved: bool,
}

impl ModelLicense {
    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn redistribution_allowed(&self) -> bool {
        self.redistribution_allowed
    }

    pub fn owner_approved(&self) -> bool {
        self.owner_approved
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelPrivacyDeclaration {
    runs_locally: bool,
    network_required: bool,
    stores_input: bool,
}

impl ModelPrivacyDeclaration {
    pub const fn is_private_local_only(self) -> bool {
        self.runs_locally && !self.network_required && !self.stores_input
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelManifest {
    schema_version: u32,
    id: String,
    display_name: String,
    version: String,
    class: ModelClass,
    runtime: ModelRuntime,
    platforms: Vec<ModelPlatform>,
    capabilities: Vec<AiFeature>,
    artifacts: Vec<ModelArtifact>,
    license: ModelLicense,
    hardware: ModelHardwareRequirements,
    privacy: ModelPrivacyDeclaration,
}

impl ModelManifest {
    pub fn from_json(json: &str) -> Result<Self, AiError> {
        let manifest = serde_json::from_str::<Self>(json).map_err(|_| manifest_invalid())?;
        manifest.validate(false)?;
        Ok(manifest)
    }

    pub fn from_template_json(json: &str) -> Result<Self, AiError> {
        let manifest = serde_json::from_str::<Self>(json).map_err(|_| manifest_invalid())?;
        manifest.validate(true)?;
        if manifest.license.owner_approved {
            return Err(AiError::new(AiErrorCode::ModelLicenseNotApproved));
        }
        Ok(manifest)
    }

    pub fn package_artifacts(mut self, package_root: &Path) -> Result<Self, AiError> {
        if self.license.owner_approved {
            return Err(AiError::new(AiErrorCode::ModelLicenseNotApproved));
        }
        for artifact in &mut self.artifacts {
            let digest = digest_package_artifact(package_root, &artifact.path)?;
            artifact.sha256 = digest.sha256;
            artifact.size_bytes = digest.size_bytes;
        }
        self.validate(false)?;
        Ok(self)
    }

    pub fn to_pretty_json(&self) -> Result<String, AiError> {
        let mut json = serde_json::to_string_pretty(self).map_err(|_| manifest_invalid())?;
        json.push('\n');
        Ok(json)
    }

    pub fn approval_fingerprint(&self) -> Result<String, AiError> {
        self.validate(false)?;

        let mut platforms = self.platforms.clone();
        platforms.sort_by_key(|platform| platform.as_str());
        let mut capabilities = self.capabilities.clone();
        capabilities.sort_by_key(|feature| feature.as_str());
        let mut artifacts = self.artifacts.iter().collect::<Vec<_>>();
        artifacts.sort_by(|left, right| left.path.cmp(&right.path));

        let payload = ApprovalFingerprintPayload {
            schema_version: self.schema_version,
            id: &self.id,
            display_name: &self.display_name,
            version: &self.version,
            class: self.class,
            runtime: self.runtime,
            platforms,
            capabilities,
            artifacts,
            license: ApprovalLicensePayload {
                name: &self.license.name,
                url: &self.license.url,
                source_url: &self.license.source_url,
                notice_path: &self.license.notice_path,
                redistribution_allowed: self.license.redistribution_allowed,
            },
            hardware: self.hardware,
            privacy: self.privacy,
        };
        let bytes = serde_json::to_vec(&payload).map_err(|_| manifest_invalid())?;
        Ok(sha256_bytes(&bytes))
    }

    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    pub fn version(&self) -> &str {
        &self.version
    }

    pub fn class(&self) -> ModelClass {
        self.class
    }

    pub fn runtime(&self) -> ModelRuntime {
        self.runtime
    }

    pub fn platforms(&self) -> &[ModelPlatform] {
        &self.platforms
    }

    pub fn capabilities(&self) -> &[AiFeature] {
        &self.capabilities
    }

    pub fn artifacts(&self) -> &[ModelArtifact] {
        &self.artifacts
    }

    pub fn license(&self) -> &ModelLicense {
        &self.license
    }

    pub fn hardware(&self) -> ModelHardwareRequirements {
        self.hardware
    }

    pub(crate) fn validate_final(&self) -> Result<(), AiError> {
        self.validate(false)
    }

    fn validate(&self, template: bool) -> Result<(), AiError> {
        if self.schema_version != MODEL_MANIFEST_SCHEMA_VERSION
            || !is_safe_identifier(&self.id, 96)
            || !is_safe_identifier(&self.version, 64)
            || !is_safe_display_name(&self.display_name)
            || self.platforms.is_empty()
            || self.capabilities.is_empty()
            || self.artifacts.is_empty()
            || self.artifacts.len() > MAX_MODEL_ARTIFACTS
            || !self.hardware.is_valid()
            || !self.privacy.is_private_local_only()
            || !is_safe_display_name(&self.license.name)
            || !is_https_url(&self.license.url)
            || !is_https_url(&self.license.source_url)
            || !is_safe_artifact_path(&self.license.notice_path)
        {
            return Err(manifest_invalid());
        }

        match self.class {
            ModelClass::Lite if self.capabilities.iter().any(|feature| !feature.is_lite()) => {
                return Err(manifest_invalid());
            }
            ModelClass::Writer
                if self
                    .capabilities
                    .iter()
                    .any(|feature| !feature.requires_writer()) =>
            {
                return Err(manifest_invalid());
            }
            _ => {}
        }
        if matches!(self.runtime, ModelRuntime::RustCompact)
            && !matches!(self.class, ModelClass::Lite)
            || matches!(self.runtime, ModelRuntime::Gguf)
                && !matches!(self.class, ModelClass::Writer)
            || self.platforms.contains(&ModelPlatform::Ios)
                && matches!(self.class, ModelClass::Writer)
        {
            return Err(manifest_invalid());
        }

        if has_duplicates(&self.platforms) || has_duplicates(&self.capabilities) {
            return Err(manifest_invalid());
        }

        let mut artifact_paths = HashSet::new();
        let mut package_size = 0_u64;
        let mut has_model = false;
        let mut notice_matches = false;
        for artifact in &self.artifacts {
            if !is_safe_artifact_path(&artifact.path)
                || !artifact_paths.insert(artifact.path.as_str())
                || (!template && !is_lower_sha256(&artifact.sha256))
                || (!template && artifact.size_bytes == 0)
                || (template && !artifact.sha256.is_empty() && !is_lower_sha256(&artifact.sha256))
            {
                return Err(manifest_invalid());
            }
            has_model |= artifact.kind == ModelArtifactKind::Model;
            notice_matches |= artifact.kind == ModelArtifactKind::LicenseNotice
                && artifact.path == self.license.notice_path;
            package_size = package_size
                .checked_add(artifact.size_bytes)
                .ok_or_else(manifest_invalid)?;
        }
        if !has_model || !notice_matches {
            return Err(manifest_invalid());
        }

        let maximum_package_size = match self.class {
            ModelClass::Lite => MAX_AI_LITE_PACKAGE_BYTES,
            ModelClass::Writer => MAX_WRITER_PACKAGE_BYTES,
        };
        if package_size > maximum_package_size {
            return Err(manifest_invalid());
        }
        Ok(())
    }
}

#[derive(Serialize)]
struct ApprovalFingerprintPayload<'a> {
    schema_version: u32,
    id: &'a str,
    display_name: &'a str,
    version: &'a str,
    class: ModelClass,
    runtime: ModelRuntime,
    platforms: Vec<ModelPlatform>,
    capabilities: Vec<AiFeature>,
    artifacts: Vec<&'a ModelArtifact>,
    license: ApprovalLicensePayload<'a>,
    hardware: ModelHardwareRequirements,
    privacy: ModelPrivacyDeclaration,
}

#[derive(Serialize)]
struct ApprovalLicensePayload<'a> {
    name: &'a str,
    url: &'a str,
    source_url: &'a str,
    notice_path: &'a str,
    redistribution_allowed: bool,
}

fn has_duplicates<T: Eq + std::hash::Hash>(values: &[T]) -> bool {
    let mut seen = HashSet::with_capacity(values.len());
    values.iter().any(|value| !seen.insert(value))
}

fn is_safe_identifier(value: &str, maximum_length: usize) -> bool {
    !value.is_empty()
        && value.len() <= maximum_length
        && value.is_ascii()
        && value
            .bytes()
            .next()
            .is_some_and(|byte| byte.is_ascii_alphanumeric())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

fn is_safe_display_name(value: &str) -> bool {
    !value.trim().is_empty() && value.chars().count() <= 128 && !value.chars().any(char::is_control)
}

fn is_https_url(value: &str) -> bool {
    const HTTPS_SCHEME: &str = concat!("https", "://");
    let remainder = value.strip_prefix(HTTPS_SCHEME).unwrap_or_default();
    !remainder.is_empty()
        && remainder.contains('.')
        && !remainder.chars().any(|character| {
            character.is_whitespace() || character.is_control() || matches!(character, '<' | '>')
        })
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
