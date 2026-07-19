use std::fmt::Write as _;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::imported_lexicon::{import_rime_file, MAX_IMPORTED_ENTRIES, MAX_RIME_SOURCE_BYTES};
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
fn repeated_imports_merge_with_existing_entries() {
    let first_source_path = temp_path("first_rime_source", "dict.yaml");
    let second_source_path = temp_path("second_rime_source", "dict.yaml");
    let imported_path = temp_path("cumulative_imported_lexicon", "tsv");
    std::fs::write(&first_source_path, "猫栈测试\tmao zhan ce shi\t900000\n")
        .expect("write first source");
    std::fs::write(&second_source_path, "本地词库\tben di ci ku\t800000\n")
        .expect("write second source");
    let settings = ImeSettings {
        imported_lexicon_path: Some(imported_path.clone()),
        ..ImeSettings::default()
    };

    let engine = ImeEngine::with_settings(settings.clone()).expect("engine");
    let first_report = engine
        .import_rime_lexicon(&first_source_path)
        .expect("first import succeeds");
    let second_report = engine
        .import_rime_lexicon(&second_source_path)
        .expect("second import succeeds");
    assert_eq!(first_report.total_entries, 1);
    assert_eq!(second_report.total_entries, 2);

    let reloaded = ImeEngine::with_settings(settings).expect("reloaded engine");
    assert!(reloaded
        .candidates_for_raw("maozhanceshi")
        .iter()
        .any(|candidate| candidate.text == "猫栈测试"));
    assert!(reloaded
        .candidates_for_raw("bendiciku")
        .iter()
        .any(|candidate| candidate.text == "本地词库"));

    let _ = std::fs::remove_file(first_source_path);
    let _ = std::fs::remove_file(second_source_path);
    let _ = std::fs::remove_file(imported_path);
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

#[test]
fn entry_limit_failure_preserves_the_existing_imported_file() {
    let source_path = temp_path("over_limit_rime_source", "dict.yaml");
    let imported_path = temp_path("full_imported_lexicon", "tsv");
    let mut canonical = String::from("phrase\tpinyin\tfrequency\n");
    for index in 0..MAX_IMPORTED_ENTRIES {
        writeln!(canonical, "{}\txian\t1", indexed_han_phrase(index))
            .expect("append canonical row");
    }
    std::fs::write(&imported_path, canonical).expect("write full imported lexicon");
    std::fs::write(&source_path, "新增词库\txin zeng ci ku\t100\n").expect("write source");
    let before = std::fs::read(&imported_path).expect("read original imported lexicon");

    assert_eq!(
        import_rime_file(&source_path, &imported_path),
        Err(ImeError::ImportedLexiconLimit)
    );
    assert_eq!(
        std::fs::read(&imported_path).expect("read preserved imported lexicon"),
        before
    );

    let _ = std::fs::remove_file(source_path);
    let _ = std::fs::remove_file(imported_path);
}

fn indexed_han_phrase(mut index: usize) -> String {
    const DIGITS: [char; 10] = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    let mut phrase = String::from("限");
    loop {
        phrase.push(DIGITS[index % DIGITS.len()]);
        index /= DIGITS.len();
        if index == 0 {
            break;
        }
    }
    phrase
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
