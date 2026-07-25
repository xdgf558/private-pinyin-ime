#![cfg(feature = "reviewed-rime-frost")]

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::reviewed_rime_frost::{
    import_reviewed_rime_frost_archive_with_manifest, ReviewedRimeFrostManifest,
};
use ime_core::ImeError;
use sha2::{Digest, Sha256};
use zip::write::SimpleFileOptions;
use zip::ZipWriter;

const CORE_MEMBERS: [&str; 6] = [
    "cn_dicts/8105.dict.yaml",
    "cn_dicts/41448.dict.yaml",
    "cn_dicts/base.dict.yaml",
    "cn_dicts/ext.dict.yaml",
    "cn_dicts/others.dict.yaml",
    "cn_dicts/corrections.dict.yaml",
];

#[test]
fn approved_archive_is_verified_parsed_and_written_atomically() {
    let archive_path = temp_path("valid_frost", "zip");
    let destination_path = temp_path("valid_frost", "tsv");
    write_archive(&archive_path, &[]);
    let (bytes, sha256) = artifact_identity(&archive_path);

    let report = import_reviewed_rime_frost_archive_with_manifest(
        &archive_path,
        &destination_path,
        ReviewedRimeFrostManifest {
            archive_bytes: bytes,
            archive_sha256: &sha256,
        },
    )
    .expect("approved archive imports");

    assert_eq!(report.accepted_rows, CORE_MEMBERS.len());
    assert_eq!(report.total_entries, CORE_MEMBERS.len());
    let output = std::fs::read_to_string(&destination_path).expect("read imported layer");
    assert!(output.starts_with("phrase\tpinyin\tfrequency\n"));
    assert!(output.contains("白霜零\tbai shuang ling\t1000\n"));

    cleanup(&[archive_path, destination_path]);
}

#[test]
fn hash_mismatch_preserves_the_previous_frost_layer() {
    let archive_path = temp_path("bad_hash_frost", "zip");
    let destination_path = temp_path("bad_hash_frost", "tsv");
    write_archive(&archive_path, &[]);
    std::fs::write(&destination_path, "previous frost layer").expect("write previous layer");
    let (bytes, _) = artifact_identity(&archive_path);

    assert_eq!(
        import_reviewed_rime_frost_archive_with_manifest(
            &archive_path,
            &destination_path,
            ReviewedRimeFrostManifest {
                archive_bytes: bytes,
                archive_sha256: &"0".repeat(64),
            },
        ),
        Err(ImeError::ReviewedLexiconArtifact)
    );
    assert_eq!(
        std::fs::read_to_string(&destination_path).expect("read preserved layer"),
        "previous frost layer"
    );

    cleanup(&[archive_path, destination_path]);
}

#[test]
fn archive_member_path_traversal_is_rejected_without_overwriting() {
    let archive_path = temp_path("traversal_frost", "zip");
    let destination_path = temp_path("traversal_frost", "tsv");
    write_archive(
        &archive_path,
        &[("../escape.dict.yaml", "恶意\t e yi\t1\n")],
    );
    std::fs::write(&destination_path, "previous frost layer").expect("write previous layer");
    let (bytes, sha256) = artifact_identity(&archive_path);

    assert_eq!(
        import_reviewed_rime_frost_archive_with_manifest(
            &archive_path,
            &destination_path,
            ReviewedRimeFrostManifest {
                archive_bytes: bytes,
                archive_sha256: &sha256,
            },
        ),
        Err(ImeError::ReviewedLexiconArchive)
    );
    assert_eq!(
        std::fs::read_to_string(&destination_path).expect("read preserved layer"),
        "previous frost layer"
    );

    cleanup(&[archive_path, destination_path]);
}

#[test]
fn archive_symlink_is_rejected_without_overwriting() {
    let archive_path = temp_path("symlink_frost", "zip");
    let destination_path = temp_path("symlink_frost", "tsv");
    let file = std::fs::File::create(&archive_path).expect("create archive");
    let mut archive = ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    write_core_members(&mut archive, options);
    archive
        .add_symlink("extra/link", "../outside", options)
        .expect("add symlink");
    archive.finish().expect("finish archive");
    std::fs::write(&destination_path, "previous frost layer").expect("write previous layer");
    let (bytes, sha256) = artifact_identity(&archive_path);

    assert_eq!(
        import_reviewed_rime_frost_archive_with_manifest(
            &archive_path,
            &destination_path,
            ReviewedRimeFrostManifest {
                archive_bytes: bytes,
                archive_sha256: &sha256,
            },
        ),
        Err(ImeError::ReviewedLexiconArchive)
    );
    assert_eq!(
        std::fs::read_to_string(&destination_path).expect("read preserved layer"),
        "previous frost layer"
    );

    cleanup(&[archive_path, destination_path]);
}

#[test]
fn excessive_compression_ratio_is_rejected_without_overwriting() {
    let archive_path = temp_path("ratio_bomb_frost", "zip");
    let destination_path = temp_path("ratio_bomb_frost", "tsv");
    let compressed_payload = "0".repeat(1024 * 1024);
    write_archive(
        &archive_path,
        &[("extra/highly-compressible.txt", compressed_payload.as_str())],
    );
    std::fs::write(&destination_path, "previous frost layer").expect("write previous layer");
    let (bytes, sha256) = artifact_identity(&archive_path);

    assert_eq!(
        import_reviewed_rime_frost_archive_with_manifest(
            &archive_path,
            &destination_path,
            ReviewedRimeFrostManifest {
                archive_bytes: bytes,
                archive_sha256: &sha256,
            },
        ),
        Err(ImeError::ReviewedLexiconArchive)
    );
    assert_eq!(
        std::fs::read_to_string(&destination_path).expect("read preserved layer"),
        "previous frost layer"
    );

    cleanup(&[archive_path, destination_path]);
}

#[test]
fn excessive_archive_entry_count_is_rejected() {
    let archive_path = temp_path("entry_bomb_frost", "zip");
    let destination_path = temp_path("entry_bomb_frost", "tsv");
    let extras = (0..251)
        .map(|index| {
            (
                format!("extra/{index}.txt"),
                format!("ignored archive member {index}"),
            )
        })
        .collect::<Vec<_>>();
    let borrowed = extras
        .iter()
        .map(|(name, contents)| (name.as_str(), contents.as_str()))
        .collect::<Vec<_>>();
    write_archive(&archive_path, &borrowed);
    let (bytes, sha256) = artifact_identity(&archive_path);

    assert_eq!(
        import_reviewed_rime_frost_archive_with_manifest(
            &archive_path,
            &destination_path,
            ReviewedRimeFrostManifest {
                archive_bytes: bytes,
                archive_sha256: &sha256,
            },
        ),
        Err(ImeError::ImportedLexiconLimit)
    );
    assert!(!destination_path.exists());

    cleanup(&[archive_path, destination_path]);
}

#[test]
fn duplicate_archive_member_is_rejected_even_when_zip_reader_deduplicates() {
    let archive_path = temp_path("duplicate_member_frost", "zip");
    let destination_path = temp_path("duplicate_member_frost", "tsv");
    const PLACEHOLDER: &str = "cn_dicts/9999.dict.yaml";
    assert_eq!(PLACEHOLDER.len(), CORE_MEMBERS[0].len());
    write_archive(&archive_path, &[(PLACEHOLDER, "重复\tchong fu\t1\n")]);
    // zip-rs deduplicates equal central-directory names. The EOCD count check
    // must reject the archive before that behavior can hide this duplicate.
    replace_equal_length_member_name(&archive_path, PLACEHOLDER, CORE_MEMBERS[0]);
    assert_rejected_and_preserved(
        &archive_path,
        &destination_path,
        ImeError::ReviewedLexiconArchive,
    );
    cleanup(&[archive_path, destination_path]);
}

#[test]
fn missing_approved_member_is_rejected_without_overwriting() {
    let archive_path = temp_path("missing_member_frost", "zip");
    let destination_path = temp_path("missing_member_frost", "tsv");
    let file = std::fs::File::create(&archive_path).expect("create archive");
    let mut archive = ZipWriter::new(file);
    let options = archive_options();
    for (index, name) in CORE_MEMBERS.iter().enumerate().skip(1) {
        write_core_member(&mut archive, options, index, name);
    }
    archive.finish().expect("finish archive");
    assert_rejected_and_preserved(
        &archive_path,
        &destination_path,
        ImeError::ReviewedLexiconArchive,
    );
    cleanup(&[archive_path, destination_path]);
}

#[test]
fn oversized_archive_member_is_rejected_without_overwriting() {
    let archive_path = temp_path("oversized_member_frost", "zip");
    let destination_path = temp_path("oversized_member_frost", "tsv");
    let file = std::fs::File::create(&archive_path).expect("create archive");
    let mut archive = ZipWriter::new(file);
    let options = archive_options();
    write_core_members(&mut archive, options);
    archive
        .start_file("extra/oversized.bin", options)
        .expect("start oversized member");
    std::io::copy(
        &mut std::io::repeat(0x5a).take(32 * 1024 * 1024 + 1),
        &mut archive,
    )
    .expect("write oversized member");
    archive.finish().expect("finish archive");
    assert_rejected_and_preserved(
        &archive_path,
        &destination_path,
        ImeError::ImportedLexiconLimit,
    );
    cleanup(&[archive_path, destination_path]);
}

#[test]
fn member_larger_than_its_declared_size_is_rejected_without_overwriting() {
    let archive_path = temp_path("false_declared_size_frost", "zip");
    let destination_path = temp_path("false_declared_size_frost", "tsv");
    write_archive(&archive_path, &[]);
    reduce_declared_uncompressed_size(&archive_path, CORE_MEMBERS[0]);
    assert_rejected_and_preserved(
        &archive_path,
        &destination_path,
        ImeError::ReviewedLexiconArchive,
    );
    cleanup(&[archive_path, destination_path]);
}

#[test]
fn member_without_unix_mode_is_rejected_without_overwriting() {
    let archive_path = temp_path("missing_unix_mode_frost", "zip");
    let destination_path = temp_path("missing_unix_mode_frost", "tsv");
    write_archive(&archive_path, &[]);
    clear_central_external_attributes(&archive_path, CORE_MEMBERS[0]);

    let file = std::fs::File::open(&archive_path).expect("open patched archive");
    let mut archive = zip::ZipArchive::new(file).expect("read patched archive");
    assert_eq!(
        archive
            .by_name(CORE_MEMBERS[0])
            .expect("find patched member")
            .unix_mode(),
        None,
        "fixture must exercise the missing-mode branch"
    );

    assert_rejected_and_preserved(
        &archive_path,
        &destination_path,
        ImeError::ReviewedLexiconArchive,
    );
    cleanup(&[archive_path, destination_path]);
}

#[test]
fn eocd_declared_entry_count_mismatch_is_rejected_without_overwriting() {
    let archive_path = temp_path("eocd_entry_mismatch_frost", "zip");
    let destination_path = temp_path("eocd_entry_mismatch_frost", "tsv");
    write_archive(&archive_path, &[]);
    reduce_eocd_entry_counts(&archive_path);
    assert_rejected_and_preserved(
        &archive_path,
        &destination_path,
        ImeError::ReviewedLexiconArchive,
    );
    cleanup(&[archive_path, destination_path]);
}

#[test]
fn nonempty_zip_comment_is_accepted() {
    let archive_path = temp_path("commented_frost", "zip");
    let destination_path = temp_path("commented_frost", "tsv");
    let file = std::fs::File::create(&archive_path).expect("create archive");
    let mut archive = ZipWriter::new(file);
    write_core_members(&mut archive, archive_options());
    archive.set_comment("reviewed White Frost fixture");
    archive.finish().expect("finish commented archive");
    let (bytes, sha256) = artifact_identity(&archive_path);

    let report = import_reviewed_rime_frost_archive_with_manifest(
        &archive_path,
        &destination_path,
        ReviewedRimeFrostManifest {
            archive_bytes: bytes,
            archive_sha256: &sha256,
        },
    )
    .expect("commented archive imports");

    assert_eq!(report.accepted_rows, CORE_MEMBERS.len());
    assert_eq!(report.total_entries, CORE_MEMBERS.len());
    cleanup(&[archive_path, destination_path]);
}

fn write_archive(path: &Path, extras: &[(&str, &str)]) {
    let file = std::fs::File::create(path).expect("create archive");
    let mut archive = ZipWriter::new(file);
    let options = archive_options();
    write_core_members(&mut archive, options);
    for (name, contents) in extras {
        archive
            .start_file(*name, options)
            .expect("start extra member");
        archive
            .write_all(contents.as_bytes())
            .expect("write extra member");
    }
    archive.finish().expect("finish archive");
}

fn write_core_members(archive: &mut ZipWriter<std::fs::File>, options: SimpleFileOptions) {
    for (index, name) in CORE_MEMBERS.iter().enumerate() {
        write_core_member(archive, options, index, name);
    }
}

fn write_core_member(
    archive: &mut ZipWriter<std::fs::File>,
    options: SimpleFileOptions,
    index: usize,
    name: &str,
) {
    archive
        .start_file(name, options)
        .expect("start core member");
    writeln!(
        archive,
        "白霜{}\tbai shuang {}\t{}",
        han_digit(index),
        pinyin_digit(index),
        1000 - index
    )
    .expect("write core member");
}

fn archive_options() -> SimpleFileOptions {
    SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o100644)
}

fn assert_rejected_and_preserved(archive_path: &Path, destination_path: &Path, expected: ImeError) {
    std::fs::write(destination_path, "previous frost layer").expect("write previous layer");
    let (bytes, sha256) = artifact_identity(archive_path);
    assert_eq!(
        import_reviewed_rime_frost_archive_with_manifest(
            archive_path,
            destination_path,
            ReviewedRimeFrostManifest {
                archive_bytes: bytes,
                archive_sha256: &sha256,
            },
        ),
        Err(expected)
    );
    assert_eq!(
        std::fs::read_to_string(destination_path).expect("read preserved layer"),
        "previous frost layer"
    );
}

fn reduce_declared_uncompressed_size(path: &Path, target_name: &str) {
    const CENTRAL_HEADER: &[u8; 4] = b"PK\x01\x02";
    const CENTRAL_FIXED_BYTES: usize = 46;
    const UNCOMPRESSED_SIZE_OFFSET: usize = 24;
    const FILE_NAME_LENGTH_OFFSET: usize = 28;

    let mut bytes = std::fs::read(path).expect("read archive bytes");
    let mut offset = 0_usize;
    let mut patched = false;
    while offset + CENTRAL_FIXED_BYTES <= bytes.len() {
        if &bytes[offset..offset + 4] != CENTRAL_HEADER {
            offset += 1;
            continue;
        }
        let name_length = u16::from_le_bytes([
            bytes[offset + FILE_NAME_LENGTH_OFFSET],
            bytes[offset + FILE_NAME_LENGTH_OFFSET + 1],
        ]) as usize;
        let name_start = offset + CENTRAL_FIXED_BYTES;
        let name_end = name_start + name_length;
        if name_end <= bytes.len() && &bytes[name_start..name_end] == target_name.as_bytes() {
            let size_offset = offset + UNCOMPRESSED_SIZE_OFFSET;
            let size = u32::from_le_bytes(
                bytes[size_offset..size_offset + 4]
                    .try_into()
                    .expect("central size bytes"),
            );
            bytes[size_offset..size_offset + 4]
                .copy_from_slice(&size.saturating_sub(1).to_le_bytes());
            patched = true;
            break;
        }
        offset = name_end;
    }
    assert!(patched, "target central directory member was not found");
    std::fs::write(path, bytes).expect("write patched archive");
}

fn clear_central_external_attributes(path: &Path, target_name: &str) {
    const CENTRAL_HEADER: &[u8; 4] = b"PK\x01\x02";
    const CENTRAL_FIXED_BYTES: usize = 46;
    const FILE_NAME_LENGTH_OFFSET: usize = 28;
    const EXTERNAL_ATTRIBUTES_OFFSET: usize = 38;

    let mut bytes = std::fs::read(path).expect("read archive bytes");
    let mut offset = 0_usize;
    let mut patched = false;
    while offset + CENTRAL_FIXED_BYTES <= bytes.len() {
        if &bytes[offset..offset + 4] != CENTRAL_HEADER {
            offset += 1;
            continue;
        }
        let name_length = u16::from_le_bytes([
            bytes[offset + FILE_NAME_LENGTH_OFFSET],
            bytes[offset + FILE_NAME_LENGTH_OFFSET + 1],
        ]) as usize;
        let name_start = offset + CENTRAL_FIXED_BYTES;
        let name_end = name_start + name_length;
        if name_end <= bytes.len() && &bytes[name_start..name_end] == target_name.as_bytes() {
            let attributes = offset + EXTERNAL_ATTRIBUTES_OFFSET;
            bytes[attributes..attributes + 4].fill(0);
            patched = true;
            break;
        }
        offset = name_end;
    }
    assert!(patched, "target central directory member was not found");
    std::fs::write(path, bytes).expect("write patched archive");
}

fn reduce_eocd_entry_counts(path: &Path) {
    const EOCD_HEADER: &[u8; 4] = b"PK\x05\x06";
    const ENTRIES_ON_DISK_OFFSET: usize = 8;
    const TOTAL_ENTRIES_OFFSET: usize = 10;

    let mut bytes = std::fs::read(path).expect("read archive bytes");
    let offset = bytes
        .windows(EOCD_HEADER.len())
        .rposition(|window| window == EOCD_HEADER)
        .expect("find EOCD");
    let total = u16::from_le_bytes([
        bytes[offset + TOTAL_ENTRIES_OFFSET],
        bytes[offset + TOTAL_ENTRIES_OFFSET + 1],
    ]);
    assert!(total > 0, "fixture must contain archive members");
    let reduced = total - 1;
    bytes[offset + ENTRIES_ON_DISK_OFFSET..offset + ENTRIES_ON_DISK_OFFSET + 2]
        .copy_from_slice(&reduced.to_le_bytes());
    bytes[offset + TOTAL_ENTRIES_OFFSET..offset + TOTAL_ENTRIES_OFFSET + 2]
        .copy_from_slice(&reduced.to_le_bytes());
    std::fs::write(path, bytes).expect("write patched archive");
}

fn replace_equal_length_member_name(path: &Path, old_name: &str, new_name: &str) {
    assert_eq!(old_name.len(), new_name.len());
    let mut bytes = std::fs::read(path).expect("read archive bytes");
    let old = old_name.as_bytes();
    let mut replacements = 0;
    let mut offset = 0;
    while let Some(relative) = bytes[offset..]
        .windows(old.len())
        .position(|window| window == old)
    {
        let start = offset + relative;
        bytes[start..start + old.len()].copy_from_slice(new_name.as_bytes());
        replacements += 1;
        offset = start + old.len();
    }
    assert_eq!(
        replacements, 2,
        "member name must appear in local and central headers"
    );
    std::fs::write(path, bytes).expect("write patched archive");
}

fn artifact_identity(path: &Path) -> (u64, String) {
    let mut file = std::fs::File::open(path).expect("open archive");
    let bytes = file.metadata().expect("archive metadata").len();
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 8192];
    loop {
        let read = file.read(&mut buffer).expect("hash archive");
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    (bytes, format!("{:x}", hasher.finalize()))
}

fn han_digit(index: usize) -> char {
    ['零', '一', '二', '三', '四', '五'][index]
}

fn pinyin_digit(index: usize) -> &'static str {
    ["ling", "yi", "er", "san", "si", "wu"][index]
}

fn temp_path(name: &str, extension: &str) -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    let path = std::env::temp_dir().join(format!(
        "private_pinyin_{name}_{}_{}.{extension}",
        std::process::id(),
        unique
    ));
    let _ = std::fs::remove_file(&path);
    path
}

fn cleanup(paths: &[PathBuf]) {
    for path in paths {
        let _ = std::fs::remove_file(path);
    }
}
