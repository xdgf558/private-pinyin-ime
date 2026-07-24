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

fn write_archive(path: &Path, extras: &[(&str, &str)]) {
    let file = std::fs::File::create(path).expect("create archive");
    let mut archive = ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
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
