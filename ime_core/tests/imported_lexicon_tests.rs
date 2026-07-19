use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::imported_lexicon::MAX_RIME_SOURCE_BYTES;
use ime_core::{ImeEngine, ImeError, ImeSettings};

#[test]
fn imported_rime_entries_are_loaded_by_new_engine_snapshots() {
    let source_path = temp_path("rime_source", "dict.yaml");
    let imported_path = temp_path("imported_lexicon", "tsv");
    std::fs::write(
        &source_path,
        "---\nname: local_demo\nversion: 1\n...\n猫栈测试\tmao zhan ce shi\t900000\n",
    )
    .expect("write source");
    let settings = ImeSettings {
        imported_lexicon_path: Some(imported_path.clone()),
        ..ImeSettings::default()
    };

    let engine = ImeEngine::with_settings(settings.clone()).expect("initial engine");
    let report = engine
        .import_rime_lexicon(&source_path)
        .expect("import succeeds");
    assert_eq!(report.accepted_rows, 1);
    assert_eq!(report.total_entries, 1);
    assert!(!engine
        .candidates_for_raw("maozhanceshi")
        .iter()
        .any(|candidate| candidate.text == "猫栈测试"));

    let reloaded = ImeEngine::with_settings(settings).expect("reloaded engine");
    assert_eq!(
        reloaded
            .candidates_for_raw("maozhanceshi")
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("猫栈测试")
    );
}

#[test]
fn malformed_imported_file_fails_soft_during_engine_creation() {
    let imported_path = temp_path("malformed_imported_lexicon", "tsv");
    std::fs::write(&imported_path, "not a canonical TSV").expect("write malformed file");
    let settings = ImeSettings {
        imported_lexicon_path: Some(imported_path),
        ..ImeSettings::default()
    };

    let engine = ImeEngine::with_settings(settings).expect("base engine remains available");
    assert_eq!(
        engine
            .candidates_for_raw("nihao")
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("你好")
    );
}

#[test]
fn import_requires_a_configured_separate_destination() {
    let source_path = temp_path("unconfigured_rime_source", "dict.yaml");
    std::fs::write(&source_path, "你好\tni hao\t100\n").expect("write source");
    let engine = ImeEngine::new().expect("engine");
    assert_eq!(
        engine.import_rime_lexicon(source_path),
        Err(ImeError::ImportedLexiconNotConfigured)
    );
}

#[test]
fn oversized_rime_sources_are_rejected_before_they_are_read() {
    let source_path = temp_path("oversized_rime_source", "dict.yaml");
    let imported_path = temp_path("oversized_imported_lexicon", "tsv");
    let source = std::fs::File::create(&source_path).expect("create sparse source");
    source
        .set_len(MAX_RIME_SOURCE_BYTES + 1)
        .expect("extend sparse source");
    let settings = ImeSettings {
        imported_lexicon_path: Some(imported_path),
        ..ImeSettings::default()
    };

    let engine = ImeEngine::with_settings(settings).expect("engine");
    assert_eq!(
        engine.import_rime_lexicon(&source_path),
        Err(ImeError::ImportedLexiconLimit)
    );

    let _ = std::fs::remove_file(source_path);
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
