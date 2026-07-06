use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::user_lexicon::UserLexicon;
use ime_core::{CandidateSource, ImeEngine, ImeSettings, KeyEvent};

struct TempDb {
    path: PathBuf,
}

impl TempDb {
    fn new(name: &str) -> Self {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or_default();
        let path = std::env::temp_dir().join(format!(
            "private_pinyin_{name}_{}_{}.sqlite",
            std::process::id(),
            unique
        ));
        let _ = std::fs::remove_file(&path);
        Self { path }
    }
}

impl Drop for TempDb {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

struct TempFile {
    path: PathBuf,
}

impl TempFile {
    fn new(name: &str, extension: &str) -> Self {
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
        Self { path }
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

fn settings_with_user_lexicon(path: PathBuf) -> ImeSettings {
    ImeSettings {
        user_lexicon_path: Some(path),
        ..ImeSettings::default()
    }
}

fn commit_first_candidate(engine: &ImeEngine, raw_input: &str) {
    let mut session = engine.create_session();
    for ch in raw_input.chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }
    session.feed_key(KeyEvent::from_char(' '));
}

#[test]
fn committing_candidate_updates_user_lexicon() {
    let temp_db = TempDb::new("learn_enabled");
    let settings = settings_with_user_lexicon(temp_db.path.clone());
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");

    commit_first_candidate(&engine, "nihao");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 1);
}

#[test]
fn learned_candidate_is_read_from_user_lexicon() {
    let temp_db = TempDb::new("learn_readback");
    let settings = settings_with_user_lexicon(temp_db.path.clone());
    let engine = ImeEngine::with_settings(settings.clone()).expect("engine opens user lexicon");

    commit_first_candidate(&engine, "nihao");

    let next_engine = ImeEngine::with_settings(settings).expect("engine reopens user lexicon");
    let candidates = next_engine.candidates_for_raw("nihao");

    assert_eq!(
        candidates.first().map(|candidate| candidate.source),
        Some(CandidateSource::User)
    );
}

#[test]
fn disabled_user_learning_does_not_write_user_lexicon() {
    let temp_db = TempDb::new("learn_disabled");
    let mut settings = settings_with_user_lexicon(temp_db.path.clone());
    settings.enable_user_learning = false;
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");

    commit_first_candidate(&engine, "nihao");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
}

#[test]
fn strict_privacy_mode_does_not_write_user_lexicon() {
    let temp_db = TempDb::new("strict_privacy");
    let mut settings = settings_with_user_lexicon(temp_db.path.clone());
    settings.strict_privacy_mode = true;
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");

    commit_first_candidate(&engine, "nihao");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
}

#[test]
fn user_lexicon_can_be_exported_and_cleared() {
    let temp_db = TempDb::new("export_clear");
    let temp_export = TempFile::new("export_clear", "tsv");
    let settings = settings_with_user_lexicon(temp_db.path.clone());
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");

    commit_first_candidate(&engine, "nihao");

    assert_eq!(
        engine
            .export_user_lexicon(&temp_export.path)
            .expect("export lexicon"),
        1
    );
    let exported = std::fs::read_to_string(&temp_export.path).expect("read export");
    assert!(exported.contains("phrase\tpinyin\tfrequency\tupdated_at_ms"));
    assert!(exported.contains("你好\tni hao\t1\t"));

    engine.clear_user_lexicon().expect("clear lexicon");
    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
}
