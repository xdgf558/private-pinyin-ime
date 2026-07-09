use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::pinyin_parser::compact_pinyin;
use ime_core::user_lexicon::UserLexicon;
use ime_core::{
    CandidateSource, ImeEngine, ImeOutput, ImeSettings, InputSession, KeyEvent, PinyinParser,
};
use rusqlite::{params, Connection};

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
    commit_first_candidate_in_session(&mut session, raw_input);
}

fn commit_first_candidate_in_session(session: &mut InputSession, raw_input: &str) -> ImeOutput {
    for ch in raw_input.chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }
    session.feed_key(KeyEvent::from_char(' '))
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
fn sequential_candidate_commits_learn_user_bigram_prediction() {
    let temp_db = TempDb::new("learn_bigram");
    let settings = settings_with_user_lexicon(temp_db.path.clone());
    let engine = ImeEngine::with_settings(settings.clone()).expect("engine opens user lexicon");
    let mut session = engine.create_session();

    let first = commit_first_candidate_in_session(&mut session, "nihao");
    let second = commit_first_candidate_in_session(&mut session, "ganma");

    assert_eq!(first.commit_text, "你好");
    assert_eq!(second.commit_text, "干嘛");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 1);

    let next_engine = ImeEngine::with_settings(settings).expect("engine reopens user lexicon");
    let mut next_session = next_engine.create_session();
    let output = commit_first_candidate_in_session(&mut next_session, "nihao");

    assert_eq!(output.commit_text, "你好");
    assert_eq!(
        output
            .candidates
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("干嘛")
    );
    assert_eq!(
        output.candidates.first().map(|candidate| candidate.source),
        Some(CandidateSource::Prediction)
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
fn disabled_user_learning_does_not_write_user_bigram() {
    let temp_db = TempDb::new("bigram_disabled");
    let mut settings = settings_with_user_lexicon(temp_db.path.clone());
    settings.enable_user_learning = false;
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");
    let mut session = engine.create_session();

    commit_first_candidate_in_session(&mut session, "nihao");
    commit_first_candidate_in_session(&mut session, "ganma");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 0);
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
fn strict_privacy_mode_does_not_write_user_bigram() {
    let temp_db = TempDb::new("strict_bigram");
    let mut settings = settings_with_user_lexicon(temp_db.path.clone());
    settings.strict_privacy_mode = true;
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");
    let mut session = engine.create_session();

    commit_first_candidate_in_session(&mut session, "nihao");
    commit_first_candidate_in_session(&mut session, "ganma");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 0);
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

#[test]
fn clear_user_lexicon_removes_user_bigram_predictions() {
    let temp_db = TempDb::new("clear_bigram");
    let temp_export = TempFile::new("clear_bigram", "tsv");
    let settings = settings_with_user_lexicon(temp_db.path.clone());
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");
    let mut session = engine.create_session();

    commit_first_candidate_in_session(&mut session, "nihao");
    commit_first_candidate_in_session(&mut session, "ganma");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 2);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 1);
    assert_eq!(
        engine
            .export_user_lexicon(&temp_export.path)
            .expect("export lexicon"),
        3
    );
    let exported = std::fs::read_to_string(&temp_export.path).expect("read export");
    assert!(exported.contains("# user_bigrams"));
    assert!(exported.contains("left_phrase\tright_phrase\tright_pinyin\tfrequency\tupdated_at_ms"));
    assert!(exported.contains("你好\t干嘛\tgan ma\t1\t"));

    engine.clear_user_lexicon().expect("clear lexicon");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 0);
}

#[test]
fn user_bigram_learning_skips_long_phrases() {
    let temp_db = TempDb::new("long_bigram");
    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon opens");

    user_lexicon
        .record_transition(
            "你好",
            "一二三四五六七八九",
            "yi er san si wu liu qi ba jiu",
        )
        .expect("record long transition is ignored");

    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 0);
}

#[test]
fn export_without_user_lexicon_writes_empty_tsv() {
    let temp_export = TempFile::new("export_without_user_lexicon", "tsv");
    let engine = ImeEngine::new().expect("engine opens without user lexicon");

    assert_eq!(
        engine
            .export_user_lexicon(&temp_export.path)
            .expect("export empty lexicon"),
        0
    );
    assert_eq!(
        std::fs::read_to_string(&temp_export.path).expect("read empty export"),
        "phrase\tpinyin\tfrequency\tupdated_at_ms\n"
    );
}

#[test]
fn user_lexicon_schema_indexes_pinyin_for_exact_lookup() {
    let temp_db = TempDb::new("pinyin_index");
    let _user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon opens");
    let connection = Connection::open(&temp_db.path).expect("open raw sqlite connection");

    let index_count: i64 = connection
        .query_row(
            "SELECT COUNT(*)
               FROM sqlite_master
              WHERE type = 'index'
                AND name = 'idx_user_phrases_pinyin'",
            [],
            |row| row.get(0),
        )
        .expect("query index");

    assert_eq!(index_count, 1);
}

#[test]
fn user_lexicon_lookup_preserves_exact_matches_before_prefix_limit() {
    let temp_db = TempDb::new("exact_before_prefix_limit");
    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon opens");
    let connection = Connection::open(&temp_db.path).expect("open raw sqlite connection");

    connection
        .execute(
            "INSERT INTO user_phrases
               (phrase, pinyin, compact_pinyin, frequency, updated_at_ms)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params!["zz rare exact", "ni", compact_pinyin("ni"), 1_i64, 1_i64],
        )
        .expect("insert exact row");

    for index in 0..60 {
        let phrase = format!("aa high prefix {index:02}");
        connection
            .execute(
                "INSERT INTO user_phrases
                   (phrase, pinyin, compact_pinyin, frequency, updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![
                    phrase,
                    "nian",
                    compact_pinyin("nian"),
                    1_000_000_i64 - i64::from(index),
                    i64::from(index)
                ],
            )
            .expect("insert prefix row");
    }

    let parses = PinyinParser.parse("ni");
    let candidates = user_lexicon
        .lookup("ni", &parses)
        .expect("lookup user candidates");

    assert_eq!(
        candidates.first().map(|candidate| candidate.text.as_str()),
        Some("zz rare exact")
    );
}
