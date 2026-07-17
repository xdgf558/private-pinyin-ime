use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::{AiError, AiErrorCode};

const READ_BUFFER_BYTES: usize = 64 * 1024;

pub(crate) struct ArtifactDigest {
    pub(crate) sha256: String,
    pub(crate) size_bytes: u64,
}

pub(crate) fn is_safe_artifact_path(path: &str) -> bool {
    if path.is_empty()
        || path.len() > 240
        || path.starts_with('/')
        || path.ends_with('/')
        || path.contains("//")
        || path.contains('\\')
        || path.contains(':')
        || !path.is_ascii()
    {
        return false;
    }

    path.split('/').all(|segment| {
        !segment.is_empty()
            && segment != "."
            && segment != ".."
            && segment
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
    })
}

pub(crate) fn digest_package_artifact(
    package_root: &Path,
    relative_path: &str,
) -> Result<ArtifactDigest, AiError> {
    let path = resolve_package_artifact(package_root, relative_path)?;
    let mut file = fs::File::open(path).map_err(|_| model_not_found())?;
    digest_reader(&mut file, None)
}

pub(crate) fn verify_package_artifact(
    package_root: &Path,
    relative_path: &str,
    expected_sha256: &str,
    expected_size_bytes: u64,
) -> Result<(), AiError> {
    let path = resolve_package_artifact(package_root, relative_path)?;
    let mut file = fs::File::open(path).map_err(|_| model_not_found())?;
    let digest = digest_reader(&mut file, Some(expected_size_bytes))?;
    if digest.size_bytes != expected_size_bytes || digest.sha256 != expected_sha256 {
        return Err(integrity_mismatch());
    }
    Ok(())
}

pub(crate) fn read_verified_package_artifact(
    package_root: &Path,
    relative_path: &str,
    expected_sha256: &str,
    expected_size_bytes: u64,
    maximum_size_bytes: u64,
) -> Result<Vec<u8>, AiError> {
    if expected_size_bytes > maximum_size_bytes || expected_size_bytes > usize::MAX as u64 {
        return Err(integrity_mismatch());
    }

    let path = resolve_package_artifact(package_root, relative_path)?;
    let mut file = fs::File::open(path).map_err(|_| model_not_found())?;
    let mut bytes = Vec::with_capacity(expected_size_bytes as usize);
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; READ_BUFFER_BYTES];
    let mut size_bytes = 0_u64;

    loop {
        let read = file.read(&mut buffer).map_err(|_| model_not_found())?;
        if read == 0 {
            break;
        }
        size_bytes = size_bytes
            .checked_add(read as u64)
            .ok_or_else(integrity_mismatch)?;
        if size_bytes > maximum_size_bytes {
            return Err(integrity_mismatch());
        }
        hasher.update(&buffer[..read]);
        bytes.extend_from_slice(&buffer[..read]);
    }

    let actual_sha256 = encode_lower_hex(&hasher.finalize());
    if size_bytes != expected_size_bytes || actual_sha256 != expected_sha256 {
        return Err(integrity_mismatch());
    }
    Ok(bytes)
}

pub(crate) fn canonical_package_root(package_root: &Path) -> Result<PathBuf, AiError> {
    let metadata = fs::symlink_metadata(package_root).map_err(|_| model_not_found())?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(manifest_invalid());
    }
    fs::canonicalize(package_root).map_err(|_| model_not_found())
}

fn resolve_package_artifact(package_root: &Path, relative_path: &str) -> Result<PathBuf, AiError> {
    if !is_safe_artifact_path(relative_path) {
        return Err(manifest_invalid());
    }

    let canonical_root = canonical_package_root(package_root)?;
    let segments = relative_path.split('/').collect::<Vec<_>>();
    let mut path = canonical_root.clone();
    for (index, segment) in segments.iter().enumerate() {
        path.push(segment);
        let metadata = fs::symlink_metadata(&path).map_err(|_| model_not_found())?;
        if metadata.file_type().is_symlink() {
            return Err(manifest_invalid());
        }
        let is_last = index + 1 == segments.len();
        if (is_last && !metadata.is_file()) || (!is_last && !metadata.is_dir()) {
            return Err(model_not_found());
        }
    }

    let canonical_path = fs::canonicalize(&path).map_err(|_| model_not_found())?;
    if !canonical_path.starts_with(&canonical_root) {
        return Err(manifest_invalid());
    }
    Ok(canonical_path)
}

fn digest_reader(
    reader: &mut impl Read,
    maximum_size_bytes: Option<u64>,
) -> Result<ArtifactDigest, AiError> {
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; READ_BUFFER_BYTES];
    let mut size_bytes = 0_u64;
    loop {
        let read = reader.read(&mut buffer).map_err(|_| model_not_found())?;
        if read == 0 {
            break;
        }
        size_bytes = size_bytes
            .checked_add(read as u64)
            .ok_or_else(integrity_mismatch)?;
        if maximum_size_bytes.is_some_and(|maximum| size_bytes > maximum) {
            return Err(integrity_mismatch());
        }
        hasher.update(&buffer[..read]);
    }
    Ok(ArtifactDigest {
        sha256: encode_lower_hex(&hasher.finalize()),
        size_bytes,
    })
}

pub(crate) fn sha256_bytes(bytes: &[u8]) -> String {
    encode_lower_hex(&Sha256::digest(bytes))
}

fn encode_lower_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

fn model_not_found() -> AiError {
    AiError::new(AiErrorCode::ModelNotFound)
}

fn manifest_invalid() -> AiError {
    AiError::new(AiErrorCode::ModelManifestInvalid)
}

fn integrity_mismatch() -> AiError {
    AiError::new(AiErrorCode::ModelIntegrityMismatch)
}
