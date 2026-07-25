use std::fmt::Write as _;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::imported_lexicon::{import_rime_file_with_limits, ImportedLexiconLimits};
use ime_core::lexicon::Lexicon;
use ime_core::{ImeEngine, ImeError, ImeSettings};

const SMALL_TEST_LIMITS: ImportedLexiconLimits = ImportedLexiconLimits::new(1024, 1024 * 1024, 32);

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
fn desktop_import_layers_remain_independent_and_respect_enable_flags() {
    let manual_path = temp_path("manual_layer", "tsv");
    let ice_path = temp_path("ice_layer", "tsv");
    let frost_path = temp_path("frost_layer", "tsv");
    write_canonical_layer(&manual_path, "手动层", "shou dong ceng");
    write_canonical_layer(&ice_path, "雾凇层", "wu song ceng");
    write_canonical_layer(&frost_path, "白霜层", "bai shuang ceng");
    Lexicon::load_embedded_with_imported(&manual_path).expect("manual layer parses");
    Lexicon::load_embedded_with_imported(&ice_path).expect("ice layer parses");
    Lexicon::load_embedded_with_imported(&frost_path).expect("frost layer parses");
    let settings = ImeSettings {
        imported_lexicon_path: Some(manual_path.clone()),
        rime_ice_lexicon_path: Some(ice_path.clone()),
        enable_rime_ice_lexicon: true,
        rime_frost_lexicon_path: Some(frost_path.clone()),
        enable_rime_frost_lexicon: true,
        ..ImeSettings::default()
    };

    let engine = ImeEngine::with_settings(settings.clone()).expect("all layers load");
    assert_candidate(&engine, "shou'dong'ceng", "手动层");
    assert_candidate(&engine, "wu'song'ceng", "雾凇层");
    assert_candidate(&engine, "bai'shuang'ceng", "白霜层");

    let disabled = ImeEngine::with_settings(ImeSettings {
        enable_rime_frost_lexicon: false,
        ..settings
    })
    .expect("disabled frost remains fail-soft");
    assert_candidate(&disabled, "shou'dong'ceng", "手动层");
    assert_candidate(&disabled, "wu'song'ceng", "雾凇层");
    assert!(!disabled
        .candidates_for_raw("bai'shuang'ceng")
        .iter()
        .any(|candidate| candidate.text == "白霜层"));

    let _ = std::fs::remove_file(manual_path);
    let _ = std::fs::remove_file(ice_path);
    let _ = std::fs::remove_file(frost_path);
}

#[test]
fn imported_entries_preserve_embedded_order_and_deduplicate_deterministically() {
    let imported_path = temp_path("deterministic_imported_lexicon", "tsv");
    let embedded = Lexicon::load_embedded().expect("embedded lexicon");
    let duplicate = embedded
        .entries()
        .first()
        .expect("embedded lexicon has entries");
    let raised_frequency = duplicate.frequency.saturating_add(1_000_000);
    std::fs::write(
        &imported_path,
        format!(
            "phrase\tpinyin\tfrequency\n{}\t{}\t{}\n顺序新词\tshun xu xin ci\t900000\n",
            duplicate.phrase, duplicate.pinyin, raised_frequency
        ),
    )
    .expect("write deterministic imported layer");

    let (first, first_errors) =
        Lexicon::load_embedded_with_imported_paths([imported_path.as_path()]);
    let (second, second_errors) =
        Lexicon::load_embedded_with_imported_paths([imported_path.as_path()]);
    assert!(first_errors.is_empty());
    assert!(second_errors.is_empty());
    let first = first.expect("first merged lexicon");
    let second = second.expect("second merged lexicon");

    let embedded_identities = embedded
        .entries()
        .iter()
        .map(|entry| (&entry.phrase, &entry.pinyin))
        .collect::<Vec<_>>();
    let first_identities = first
        .entries()
        .iter()
        .map(|entry| (&entry.phrase, &entry.pinyin))
        .collect::<Vec<_>>();
    let second_identities = second
        .entries()
        .iter()
        .map(|entry| (&entry.phrase, &entry.pinyin))
        .collect::<Vec<_>>();

    assert_eq!(
        &first_identities[..embedded_identities.len()],
        embedded_identities.as_slice()
    );
    assert_eq!(first_identities, second_identities);
    assert_eq!(first.entries().len(), embedded.entries().len() + 1);
    assert_eq!(first.entries()[0].frequency, raised_frequency);
    assert_eq!(
        first.entries().last().map(|entry| entry.phrase.as_str()),
        Some("顺序新词")
    );

    let _ = std::fs::remove_file(imported_path);
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
        .set_len(SMALL_TEST_LIMITS.max_source_bytes + 1)
        .expect("extend sparse source");

    assert_eq!(
        import_rime_file_with_limits(&source_path, &imported_path, SMALL_TEST_LIMITS),
        Err(ImeError::ImportedLexiconLimit)
    );

    let _ = std::fs::remove_file(source_path);
}

#[test]
fn entry_limit_failure_preserves_the_existing_imported_file() {
    let source_path = temp_path("over_limit_rime_source", "dict.yaml");
    let imported_path = temp_path("full_imported_lexicon", "tsv");
    let mut canonical = String::from("phrase\tpinyin\tfrequency\n");
    for index in 0..SMALL_TEST_LIMITS.max_entries {
        writeln!(canonical, "{}\txian\t1", indexed_han_phrase(index))
            .expect("append canonical row");
    }
    std::fs::write(&imported_path, canonical).expect("write full imported lexicon");
    std::fs::write(&source_path, "新增词库\txin zeng ci ku\t100\n").expect("write source");
    let before = std::fs::read(&imported_path).expect("read original imported lexicon");

    assert_eq!(
        import_rime_file_with_limits(&source_path, &imported_path, SMALL_TEST_LIMITS),
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

fn write_canonical_layer(path: &std::path::Path, phrase: &str, pinyin: &str) {
    std::fs::write(
        path,
        format!("phrase\tpinyin\tfrequency\n{phrase}\t{pinyin}\t900000\n"),
    )
    .expect("write canonical layer");
}

fn assert_candidate(engine: &ImeEngine, raw: &str, expected: &str) {
    let candidates = engine.candidates_for_raw(raw);
    assert!(
        candidates
            .iter()
            .any(|candidate| candidate.text == expected),
        "missing candidate {expected} for {raw}; got {:?}",
        candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>()
    );
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
