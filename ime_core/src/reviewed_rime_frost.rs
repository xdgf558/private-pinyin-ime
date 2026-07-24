use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{BufReader, Read};
use std::path::{Component, Path};

use sha2::{Digest, Sha256};
use zip::ZipArchive;

use crate::error::{ImeError, ImeResult};
use crate::imported_lexicon::{
    deduplicate_entries, parse_rime_dictionary_with_limits, write_canonical_tsv,
    ImportedLexiconLimits, ImportedLexiconReport,
};
use crate::lexicon::LexiconEntry;

pub const RIME_FROST_DISPLAY_NAME: &str = "白霜拼音核心词库";
pub const RIME_FROST_APPROVED_VERSION: &str = "1.0.4";
pub const RIME_FROST_RELEASE_URL: &str =
    "https://github.com/gaboolic/rime-frost/releases/tag/1.0.4";
pub const RIME_FROST_ARCHIVE_URL: &str =
    "https://github.com/gaboolic/rime-frost/releases/download/1.0.4/rime-frost-schemas.zip";
pub const RIME_FROST_LATEST_RELEASE_API_URL: &str =
    "https://api.github.com/repos/gaboolic/rime-frost/releases/latest";
pub const RIME_FROST_LICENSE_URL: &str =
    "https://github.com/gaboolic/rime-frost/blob/master/LICENSE";
pub const RIME_FROST_ARCHIVE_BYTES: u64 = 44_008_360;
pub const RIME_FROST_ARCHIVE_SHA256: &str =
    "4f4998ae83f63d757c0a4ace192f69d48265bddfabe231642b73e3739ed0f2f5";

const MAX_ARCHIVE_ENTRIES: usize = 256;
const MAX_ARCHIVE_EXPANDED_BYTES: u64 = 128 * 1024 * 1024;
const MAX_ARCHIVE_MEMBER_BYTES: u64 = 32 * 1024 * 1024;
const MAX_COMPRESSION_RATIO: u64 = 200;
const RIME_FROST_LIMITS: ImportedLexiconLimits =
    ImportedLexiconLimits::new(32 * 1024 * 1024, 128 * 1024 * 1024, 750_000);
const CORE_DICTIONARY_MEMBERS: [&str; 6] = [
    "cn_dicts/8105.dict.yaml",
    "cn_dicts/41448.dict.yaml",
    "cn_dicts/base.dict.yaml",
    "cn_dicts/ext.dict.yaml",
    "cn_dicts/others.dict.yaml",
    "cn_dicts/corrections.dict.yaml",
];

#[derive(Debug, Clone, Copy)]
pub struct ReviewedRimeFrostManifest<'a> {
    pub archive_bytes: u64,
    pub archive_sha256: &'a str,
}

impl Default for ReviewedRimeFrostManifest<'static> {
    fn default() -> Self {
        Self {
            archive_bytes: RIME_FROST_ARCHIVE_BYTES,
            archive_sha256: RIME_FROST_ARCHIVE_SHA256,
        }
    }
}

pub fn import_reviewed_rime_frost_archive(
    archive_path: impl AsRef<Path>,
    destination_path: impl AsRef<Path>,
) -> ImeResult<ImportedLexiconReport> {
    import_reviewed_rime_frost_archive_with_manifest(
        archive_path,
        destination_path,
        ReviewedRimeFrostManifest::default(),
    )
}

pub fn import_reviewed_rime_frost_archive_with_manifest(
    archive_path: impl AsRef<Path>,
    destination_path: impl AsRef<Path>,
    manifest: ReviewedRimeFrostManifest<'_>,
) -> ImeResult<ImportedLexiconReport> {
    let archive_path = archive_path.as_ref();
    verify_artifact(archive_path, manifest)?;

    let file = File::open(archive_path).map_err(|_| ImeError::ImportedLexiconIo)?;
    let mut archive =
        ZipArchive::new(BufReader::new(file)).map_err(|_| ImeError::ReviewedLexiconArchive)?;
    if archive.len() > MAX_ARCHIVE_ENTRIES {
        return Err(ImeError::ImportedLexiconLimit);
    }

    let selected = CORE_DICTIONARY_MEMBERS.into_iter().collect::<HashSet<_>>();
    let mut seen_names = HashSet::with_capacity(archive.len());
    let mut expanded_bytes = 0_u64;
    let mut entries = Vec::<LexiconEntry>::new();
    let mut accepted_rows = 0_usize;
    let mut skipped_rows = 0_usize;

    for index in 0..archive.len() {
        let member = archive
            .by_index(index)
            .map_err(|_| ImeError::ReviewedLexiconArchive)?;
        let name = member.name().to_owned();
        validate_member_name(&name)?;
        if !seen_names.insert(name.clone()) {
            return Err(ImeError::ReviewedLexiconArchive);
        }
        validate_member_type(member.unix_mode(), member.is_dir())?;

        let member_bytes = member.size();
        let compressed_bytes = member.compressed_size();
        if member_bytes > MAX_ARCHIVE_MEMBER_BYTES {
            return Err(ImeError::ImportedLexiconLimit);
        }
        expanded_bytes = expanded_bytes
            .checked_add(member_bytes)
            .ok_or(ImeError::ImportedLexiconLimit)?;
        if expanded_bytes > MAX_ARCHIVE_EXPANDED_BYTES {
            return Err(ImeError::ImportedLexiconLimit);
        }
        if member_bytes > 0
            && (compressed_bytes == 0
                || member_bytes
                    > compressed_bytes
                        .checked_mul(MAX_COMPRESSION_RATIO)
                        .ok_or(ImeError::ImportedLexiconLimit)?)
        {
            return Err(ImeError::ReviewedLexiconArchive);
        }

        if selected.contains(name.as_str()) {
            let mut source = String::new();
            member
                .take(member_bytes.saturating_add(1))
                .read_to_string(&mut source)
                .map_err(|_| ImeError::ReviewedLexiconArchive)?;
            if source.len() as u64 > member_bytes {
                return Err(ImeError::ReviewedLexiconArchive);
            }
            let (incoming, skipped) =
                parse_rime_dictionary_with_limits(&source, RIME_FROST_LIMITS)?;
            accepted_rows = accepted_rows
                .checked_add(incoming.len())
                .ok_or(ImeError::ImportedLexiconLimit)?;
            skipped_rows = skipped_rows
                .checked_add(skipped)
                .ok_or(ImeError::ImportedLexiconLimit)?;
            entries.extend(incoming);
            if entries.len() > RIME_FROST_LIMITS.max_entries {
                return Err(ImeError::ImportedLexiconLimit);
            }
        }
    }

    if !CORE_DICTIONARY_MEMBERS
        .iter()
        .all(|member| seen_names.contains(*member))
    {
        return Err(ImeError::ReviewedLexiconArchive);
    }

    let entries = deduplicate_entries(entries);
    write_canonical_tsv(destination_path.as_ref(), &entries, RIME_FROST_LIMITS)?;
    Ok(ImportedLexiconReport {
        accepted_rows,
        skipped_rows,
        total_entries: entries.len(),
    })
}

fn verify_artifact(archive_path: &Path, manifest: ReviewedRimeFrostManifest<'_>) -> ImeResult<()> {
    let metadata = fs::metadata(archive_path).map_err(|_| ImeError::ImportedLexiconIo)?;
    if !metadata.is_file() || metadata.len() != manifest.archive_bytes {
        return Err(ImeError::ReviewedLexiconArtifact);
    }

    let mut reader =
        BufReader::new(File::open(archive_path).map_err(|_| ImeError::ImportedLexiconIo)?);
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = reader
            .read(&mut buffer)
            .map_err(|_| ImeError::ImportedLexiconIo)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    let actual = hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    if actual != manifest.archive_sha256 {
        return Err(ImeError::ReviewedLexiconArtifact);
    }
    Ok(())
}

fn validate_member_name(name: &str) -> ImeResult<()> {
    if name.is_empty() || name.contains('\\') || name.contains('\0') {
        return Err(ImeError::ReviewedLexiconArchive);
    }
    for component in Path::new(name).components() {
        match component {
            Component::Normal(_) => {}
            _ => return Err(ImeError::ReviewedLexiconArchive),
        }
    }
    Ok(())
}

fn validate_member_type(unix_mode: Option<u32>, is_directory: bool) -> ImeResult<()> {
    let Some(mode) = unix_mode else {
        return Ok(());
    };
    let file_type = mode & 0o170000;
    let expected = if is_directory { 0o040000 } else { 0o100000 };
    if file_type != 0 && file_type != expected {
        return Err(ImeError::ReviewedLexiconArchive);
    }
    Ok(())
}
