use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use private_pinyin_local_ai_core::ModelManifest;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageSummary {
    model_id: String,
    version: String,
    artifact_count: usize,
    approval_fingerprint_sha256: String,
}

impl PackageSummary {
    pub fn model_id(&self) -> &str {
        &self.model_id
    }

    pub fn version(&self) -> &str {
        &self.version
    }

    pub fn artifact_count(&self) -> usize {
        self.artifact_count
    }

    pub fn approval_fingerprint_sha256(&self) -> &str {
        &self.approval_fingerprint_sha256
    }
}

pub fn package_model(
    template_path: &Path,
    package_root: &Path,
    output_path: &Path,
) -> Result<PackageSummary, String> {
    let template =
        fs::read_to_string(template_path).map_err(|_| "MODEL_TEMPLATE_READ_FAILED".to_owned())?;
    let manifest = ModelManifest::from_template_json(&template)
        .map_err(|error| error.to_string())?
        .package_artifacts(package_root)
        .map_err(|error| error.to_string())?;
    let json = manifest
        .to_pretty_json()
        .map_err(|error| error.to_string())?;
    let fingerprint = manifest
        .approval_fingerprint()
        .map_err(|error| error.to_string())?;

    let mut output =
        AtomicOutput::create(output_path).map_err(|_| "MODEL_MANIFEST_WRITE_FAILED".to_owned())?;
    output
        .write_all(json.as_bytes())
        .map_err(|_| "MODEL_MANIFEST_WRITE_FAILED".to_owned())?;
    output
        .finish()
        .map_err(|_| "MODEL_MANIFEST_WRITE_FAILED".to_owned())?;

    Ok(PackageSummary {
        model_id: manifest.id().to_owned(),
        version: manifest.version().to_owned(),
        artifact_count: manifest.artifacts().len(),
        approval_fingerprint_sha256: fingerprint,
    })
}

struct AtomicOutput {
    target_path: PathBuf,
    temporary_path: PathBuf,
    file: Option<fs::File>,
    finished: bool,
}

impl AtomicOutput {
    fn create(target_path: &Path) -> io::Result<Self> {
        let target_path = target_path.to_path_buf();
        if let Some(parent) = target_path.parent() {
            fs::create_dir_all(parent)?;
        }
        let temporary_path = unique_sibling_path(&target_path, "tmp");
        let file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary_path)?;
        Ok(Self {
            target_path,
            temporary_path,
            file: Some(file),
            finished: false,
        })
    }

    fn finish(mut self) -> io::Result<()> {
        let file = self
            .file
            .take()
            .ok_or_else(|| io::Error::other("atomic output already closed"))?;
        file.sync_all()?;
        drop(file);
        replace_file(&self.temporary_path, &self.target_path)?;
        self.finished = true;
        Ok(())
    }
}

impl Write for AtomicOutput {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.file
            .as_mut()
            .ok_or_else(|| io::Error::other("atomic output already closed"))?
            .write(buffer)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file
            .as_mut()
            .ok_or_else(|| io::Error::other("atomic output already closed"))?
            .flush()
    }
}

impl Drop for AtomicOutput {
    fn drop(&mut self) {
        if !self.finished {
            let _ = fs::remove_file(&self.temporary_path);
        }
    }
}

#[cfg(not(windows))]
fn replace_file(temporary_path: &Path, target_path: &Path) -> io::Result<()> {
    fs::rename(temporary_path, target_path)
}

#[cfg(windows)]
fn replace_file(temporary_path: &Path, target_path: &Path) -> io::Result<()> {
    match fs::rename(temporary_path, target_path) {
        Ok(()) => return Ok(()),
        Err(error) if target_path.exists() => {
            if error.kind() != io::ErrorKind::AlreadyExists
                && error.kind() != io::ErrorKind::PermissionDenied
            {
                return Err(error);
            }
        }
        Err(error) => return Err(error),
    }

    let backup_path = unique_sibling_path(target_path, "bak");
    fs::rename(target_path, &backup_path)?;
    match fs::rename(temporary_path, target_path) {
        Ok(()) => {
            let _ = fs::remove_file(&backup_path);
            Ok(())
        }
        Err(error) => {
            let _ = fs::rename(&backup_path, target_path);
            Err(error)
        }
    }
}

fn unique_sibling_path(target_path: &Path, extension: &str) -> PathBuf {
    let parent = target_path.parent().unwrap_or_else(|| Path::new("."));
    let file_name = target_path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("model-manifest.json");
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    parent.join(format!(
        ".{file_name}.{}.{}.{extension}",
        std::process::id(),
        nonce
    ))
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU64, Ordering};

    use super::*;

    static NEXT_TEST_DIRECTORY: AtomicU64 = AtomicU64::new(1);
    const TEMPLATE: &str = include_str!("../../../ai/model_manifest.template.example.json");

    struct TestDirectory {
        root: PathBuf,
    }

    impl TestDirectory {
        fn new() -> Self {
            let nonce = NEXT_TEST_DIRECTORY.fetch_add(1, Ordering::Relaxed);
            let root = std::env::temp_dir().join(format!(
                "private-pinyin-model-packager-{}-{nonce}",
                std::process::id()
            ));
            fs::create_dir_all(root.join("model")).expect("create package test directory");
            fs::write(root.join("model/model.bin"), b"synthetic compact scorer")
                .expect("write model fixture");
            fs::write(root.join("LICENSE.txt"), b"Synthetic notice\n")
                .expect("write license fixture");
            Self { root }
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    fn packager_hashes_artifacts_and_writes_an_unapproved_manifest_atomically() {
        let directory = TestDirectory::new();
        let template_path = directory.root.join("template.json");
        let output_path = directory.root.join("output/manifest.json");
        fs::write(&template_path, TEMPLATE).expect("write template fixture");

        let summary = package_model(&template_path, &directory.root, &output_path)
            .expect("package synthetic model");
        assert_eq!(summary.model_id(), "private-pinyin.ai-lite.example");
        assert_eq!(summary.version(), "0.0.0");
        assert_eq!(summary.artifact_count(), 2);
        assert_eq!(summary.approval_fingerprint_sha256().len(), 64);

        let manifest_json = fs::read_to_string(output_path).expect("read packaged manifest");
        let manifest = ModelManifest::from_json(&manifest_json).expect("parse packaged manifest");
        assert!(!manifest.license().owner_approved());
        assert!(manifest
            .artifacts()
            .iter()
            .all(|artifact| artifact.size_bytes() > 0 && artifact.sha256().len() == 64));
    }

    #[test]
    fn packager_rejects_a_template_that_claims_owner_approval() {
        let directory = TestDirectory::new();
        let template_path = directory.root.join("template.json");
        let output_path = directory.root.join("manifest.json");
        fs::write(
            &template_path,
            TEMPLATE.replace("\"owner_approved\": false", "\"owner_approved\": true"),
        )
        .expect("write preapproved template");

        let error = package_model(&template_path, &directory.root, &output_path)
            .expect_err("packager must not create approval");
        assert_eq!(error, "AI_MODEL_LICENSE_NOT_APPROVED");
        assert!(!output_path.exists());
    }
}
