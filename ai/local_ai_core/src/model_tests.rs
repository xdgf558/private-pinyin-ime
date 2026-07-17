use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use crate::model_verifier::ModelApprovalRegistry;
use crate::{
    AiErrorCode, AiLiteRanker, HardwareProfile, HardwareTier, ModelManifest, ModelPackageVerifier,
    ModelPlatform,
};

static NEXT_TEST_DIRECTORY: AtomicU64 = AtomicU64::new(1);

const MODEL_BYTES: &[u8] = b"private-pinyin-synthetic-model-v1";
const NOTICE_BYTES: &[u8] = b"Synthetic test license notice.\n";
const TEMPLATE: &str = include_str!("../../model_manifest.template.example.json");

struct TestPackage {
    root: PathBuf,
}

impl TestPackage {
    fn new() -> Self {
        let nonce = NEXT_TEST_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        let root = std::env::temp_dir().join(format!(
            "private-pinyin-ai05-{}-{nonce}",
            std::process::id()
        ));
        fs::create_dir_all(root.join("model")).expect("create test model directory");
        fs::write(root.join("model/model.bin"), MODEL_BYTES).expect("write synthetic model");
        fs::write(root.join("LICENSE.txt"), NOTICE_BYTES).expect("write synthetic notice");
        Self { root }
    }

    fn root(&self) -> &Path {
        &self.root
    }
}

impl Drop for TestPackage {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn template_json() -> String {
    TEMPLATE
        .replace(
            "private-pinyin.ai-lite.example",
            "private-pinyin.synthetic-lite",
        )
        .replace("\"version\": \"0.0.0\"", "\"version\": \"1.0.0\"")
        .replace(
            "\"redistribution_allowed\": false",
            "\"redistribution_allowed\": true",
        )
}

fn packaged_manifest(package: &TestPackage) -> ModelManifest {
    ModelManifest::from_template_json(&template_json())
        .expect("parse synthetic template")
        .package_artifacts(package.root())
        .expect("package synthetic artifacts")
}

fn owner_approved_manifest(manifest: &ModelManifest) -> ModelManifest {
    let json = manifest
        .to_pretty_json()
        .expect("serialize packaged manifest")
        .replace("\"owner_approved\": false", "\"owner_approved\": true");
    ModelManifest::from_json(&json).expect("parse owner-approved manifest")
}

fn approval_registry(manifest: &ModelManifest) -> ModelApprovalRegistry {
    let fingerprint = manifest
        .approval_fingerprint()
        .expect("fingerprint approved manifest");
    ModelApprovalRegistry::from_json(&format!(
        r#"{{
  "schema_version": 1,
  "approvals": [{{
    "approval_id": "owner-ai05-test-approval",
    "model_id": "{}",
    "version": "{}",
    "manifest_fingerprint_sha256": "{}"
  }}]
}}"#,
        manifest.id(),
        manifest.version(),
        fingerprint
    ))
    .expect("parse approval registry")
}

fn supported_hardware() -> HardwareProfile {
    HardwareProfile::from_memory_gib(16, false)
}

#[test]
fn hardware_tiers_follow_the_four_eight_sixteen_twenty_four_gib_policy() {
    assert_eq!(
        HardwareTier::from_memory_bytes(4 * 1024_u64.pow(3)),
        HardwareTier::Tier0
    );
    assert_eq!(
        HardwareTier::from_memory_bytes(8 * 1024_u64.pow(3)),
        HardwareTier::Tier1
    );
    assert_eq!(
        HardwareTier::from_memory_bytes(16 * 1024_u64.pow(3)),
        HardwareTier::Tier2
    );
    assert_eq!(
        HardwareTier::from_memory_bytes(24 * 1024_u64.pow(3)),
        HardwareTier::Tier3
    );
}

#[test]
fn embedded_registry_contains_the_owner_approved_ai06_ranker() {
    let registry = ModelApprovalRegistry::embedded().expect("embedded registry must parse");
    assert_eq!(registry.approval_count(), 1);
}

#[test]
fn checked_in_ai06_ranker_verifies_and_loads_on_every_declared_platform() {
    let package_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../models/private-pinyin-ai-lite-ranker-v1");
    let manifest_json = fs::read_to_string(package_root.join("manifest.json"))
        .expect("read checked-in ranker manifest");
    let manifest = ModelManifest::from_json(&manifest_json).expect("parse ranker manifest");

    for platform in [
        ModelPlatform::Macos,
        ModelPlatform::Windows,
        ModelPlatform::Ios,
    ] {
        let verified = ModelPackageVerifier::new(platform, supported_hardware())
            .expect("embedded registry must parse")
            .verify(&package_root, &manifest)
            .expect("approved ranker package must verify");
        let ranker = AiLiteRanker::from_verified_package(&verified)
            .expect("approved ranker model must load");
        assert_eq!(ranker.model_id(), "private-pinyin.ai-lite-ranker");
        assert_eq!(ranker.model_version(), "1.0.0");
    }
}

#[test]
fn exact_external_approval_and_integrity_allow_a_synthetic_package() {
    let package = TestPackage::new();
    let packaged = packaged_manifest(&package);
    let approved = owner_approved_manifest(&packaged);
    assert_eq!(
        packaged
            .approval_fingerprint()
            .expect("packaged fingerprint"),
        approved
            .approval_fingerprint()
            .expect("approved fingerprint"),
        "the self-asserted approval bit is deliberately excluded from the external fingerprint"
    );
    let registry = approval_registry(&approved);
    let verified = ModelPackageVerifier::new_with_registry(
        registry,
        ModelPlatform::Macos,
        supported_hardware(),
    )
    .verify(package.root(), &approved)
    .expect("approved synthetic package must verify");

    assert_eq!(verified.artifact_count(), 2);
    assert_eq!(
        verified
            .read_primary_model_bytes(1024)
            .expect("verified model bytes"),
        MODEL_BYTES
    );
    let debug = format!("{verified:?}");
    assert!(debug.contains("private-pinyin.synthetic-lite"));
    assert!(!debug.contains(package.root().to_string_lossy().as_ref()));
}

#[test]
fn manifest_self_approval_without_registry_approval_is_rejected() {
    let package = TestPackage::new();
    let approved = owner_approved_manifest(&packaged_manifest(&package));
    let error = ModelPackageVerifier::new(ModelPlatform::Macos, supported_hardware())
        .expect("embedded registry must parse")
        .verify(package.root(), &approved)
        .expect_err("a manifest cannot approve itself");
    assert_eq!(error.code(), AiErrorCode::ModelLicenseNotApproved);
}

#[test]
fn corrupt_artifact_is_rejected_before_loading() {
    let package = TestPackage::new();
    let approved = owner_approved_manifest(&packaged_manifest(&package));
    let registry = approval_registry(&approved);
    fs::write(package.root().join("model/model.bin"), b"corrupt")
        .expect("corrupt synthetic artifact");

    let error = ModelPackageVerifier::new_with_registry(
        registry,
        ModelPlatform::Macos,
        supported_hardware(),
    )
    .verify(package.root(), &approved)
    .expect_err("corrupt package must fail");
    assert_eq!(error.code(), AiErrorCode::ModelIntegrityMismatch);
}

#[test]
fn oversized_corrupt_artifact_is_rejected_before_loading() {
    let package = TestPackage::new();
    let approved = owner_approved_manifest(&packaged_manifest(&package));
    let registry = approval_registry(&approved);
    fs::write(
        package.root().join("model/model.bin"),
        vec![b'x'; MODEL_BYTES.len() + 128 * 1024],
    )
    .expect("grow synthetic artifact beyond its declared size");

    let error = ModelPackageVerifier::new_with_registry(
        registry,
        ModelPlatform::Macos,
        supported_hardware(),
    )
    .verify(package.root(), &approved)
    .expect_err("oversized package must fail without unbounded hashing");
    assert_eq!(error.code(), AiErrorCode::ModelIntegrityMismatch);
}

#[test]
fn artifact_is_reverified_when_bytes_are_opened_for_inference() {
    let package = TestPackage::new();
    let approved = owner_approved_manifest(&packaged_manifest(&package));
    let registry = approval_registry(&approved);
    let verified = ModelPackageVerifier::new_with_registry(
        registry,
        ModelPlatform::Macos,
        supported_hardware(),
    )
    .verify(package.root(), &approved)
    .expect("initial package verification");

    fs::write(
        package.root().join("model/model.bin"),
        b"changed-after-verification",
    )
    .expect("change verified artifact");
    let error = verified
        .read_primary_model_bytes(1024)
        .expect_err("use-time verification must catch replacement");
    assert_eq!(error.code(), AiErrorCode::ModelIntegrityMismatch);
}

#[test]
fn unsupported_platform_and_hardware_fail_with_specific_codes() {
    let package = TestPackage::new();
    let approved = owner_approved_manifest(&packaged_manifest(&package));
    let registry = approval_registry(&approved);
    let platform_json = approved.to_pretty_json().expect("manifest json").replace(
        "\"macos\",\n    \"windows\",\n    \"ios\"",
        "\"windows\",\n    \"ios\"",
    );
    let windows_and_ios = ModelManifest::from_json(&platform_json).expect("platform manifest");
    let platform_error = ModelPackageVerifier::new_with_registry(
        approval_registry(&windows_and_ios),
        ModelPlatform::Macos,
        supported_hardware(),
    )
    .verify(package.root(), &windows_and_ios)
    .expect_err("unsupported platform must fail");
    assert_eq!(platform_error.code(), AiErrorCode::ModelPlatformUnsupported);

    let hardware_error = ModelPackageVerifier::new_with_registry(
        registry,
        ModelPlatform::Macos,
        HardwareProfile::from_memory_gib(4, false),
    )
    .verify(package.root(), &approved)
    .expect_err("low-memory hardware must fail");
    assert_eq!(hardware_error.code(), AiErrorCode::HardwareTooLow);

    let tier_zero_json = approved
        .to_pretty_json()
        .expect("manifest json")
        .replace("\"min_tier\": \"tier_1\"", "\"min_tier\": \"tier_0\"")
        .replace("\"min_memory_mb\": 8192", "\"min_memory_mb\": 1")
        .replace(
            "\"recommended_memory_mb\": 16384",
            "\"recommended_memory_mb\": 1",
        );
    let tier_zero_manifest = ModelManifest::from_json(&tier_zero_json).expect("tier-zero manifest");
    let tier_zero_error = ModelPackageVerifier::new_with_registry(
        approval_registry(&tier_zero_manifest),
        ModelPlatform::Macos,
        HardwareProfile::from_memory_gib(4, false),
    )
    .verify(package.root(), &tier_zero_manifest)
    .expect_err("tier zero must disable model inference even when a manifest asks for it");
    assert_eq!(tier_zero_error.code(), AiErrorCode::HardwareTooLow);
}

#[test]
fn unsafe_paths_and_non_private_declarations_are_rejected() {
    let unsafe_path = template_json().replace("model/model.bin", "../model.bin");
    let path_error =
        ModelManifest::from_template_json(&unsafe_path).expect_err("parent traversal must fail");
    assert_eq!(path_error.code(), AiErrorCode::ModelManifestInvalid);

    let network_required =
        template_json().replace("\"network_required\": false", "\"network_required\": true");
    let privacy_error = ModelManifest::from_template_json(&network_required)
        .expect_err("network-dependent model must fail");
    assert_eq!(privacy_error.code(), AiErrorCode::ModelManifestInvalid);
}

#[test]
fn packager_template_cannot_claim_owner_approval() {
    let preapproved =
        template_json().replace("\"owner_approved\": false", "\"owner_approved\": true");
    let error = ModelManifest::from_template_json(&preapproved)
        .expect_err("packager must not manufacture Owner approval");
    assert_eq!(error.code(), AiErrorCode::ModelLicenseNotApproved);
}

#[cfg(unix)]
#[test]
fn symbolic_link_artifacts_are_rejected() {
    use std::os::unix::fs::symlink;

    let package = TestPackage::new();
    let external = package.root().join("outside.bin");
    fs::write(&external, MODEL_BYTES).expect("write external target");
    fs::remove_file(package.root().join("model/model.bin")).expect("remove model file");
    symlink(&external, package.root().join("model/model.bin")).expect("create model symlink");

    let error = ModelManifest::from_template_json(&template_json())
        .expect("parse template")
        .package_artifacts(package.root())
        .expect_err("symbolic links must fail closed");
    assert_eq!(error.code(), AiErrorCode::ModelManifestInvalid);
}
