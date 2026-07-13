use std::path::PathBuf;
use std::sync::{Arc, Barrier};
use std::time::{SystemTime, UNIX_EPOCH};

use ime_core::lexicon::Lexicon;
use ime_core::pinyin_parser::compact_pinyin;
use ime_core::predictor::Predictor;
use ime_core::session::MAX_CONTEXT_TOKENS;
use ime_core::user_lexicon::{UserLearningLimits, UserLexicon};
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

fn current_time_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or_default()
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
fn learned_candidate_is_available_to_nine_key_lookup() {
    let temp_db = TempDb::new("nine_key_learn_readback");
    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon opens");
    user_lexicon
        .record_selection("私有候选", "ni hao")
        .expect("selection records");

    let candidates = user_lexicon
        .lookup_nine_key("64426")
        .expect("nine-key lookup succeeds");

    assert_eq!(
        candidates.first().map(|candidate| candidate.text.as_str()),
        Some("私有候选")
    );
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
fn learned_bigram_reranks_ambiguous_continuous_sentence() {
    let temp_db = TempDb::new("continuous_bigram_rerank");
    let user_lexicon = Arc::new(UserLexicon::open(&temp_db.path).expect("user lexicon opens"));
    user_lexicon
        .record_transition("今天", "天气", "tian qi")
        .expect("transition records");
    let lexicon = Arc::new(
        Lexicon::from_tsv(
            "今天\tjin tian\t1000\n天气\ttian qi\t1000\n今\tjin\t100000\n天天\ttian tian\t100000\n期\tqi\t100000\n",
        )
        .expect("test lexicon loads"),
    );
    let predictor =
        Arc::new(Predictor::from_tsv("left\tright\tfrequency\n").expect("empty predictor loads"));
    let mut session = InputSession::new(
        lexicon,
        predictor,
        Some(user_lexicon),
        ImeSettings::default(),
    );

    let mut output = ImeOutput::idle(session.mode());
    for ch in "jintiantianqi".chars() {
        output = session.feed_key(KeyEvent::from_char(ch));
    }

    assert_eq!(
        output
            .candidates
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("今天天气")
    );
}

#[test]
fn selecting_continuous_sentence_learns_internal_word_transitions() {
    let temp_db = TempDb::new("continuous_internal_learning");
    let user_lexicon = Arc::new(UserLexicon::open(&temp_db.path).expect("user lexicon opens"));
    let lexicon = Arc::new(
        Lexicon::from_tsv(
            "今天\tjin tian\t1000\n天气\ttian qi\t1000\n今\tjin\t100000\n天天\ttian tian\t100000\n期\tqi\t100000\n",
        )
        .expect("test lexicon loads"),
    );
    let predictor =
        Arc::new(Predictor::from_tsv("今天\t天气\t1000000\n").expect("predictor loads"));
    let mut session = InputSession::new(
        lexicon,
        predictor,
        Some(user_lexicon.clone()),
        ImeSettings::default(),
    );

    let commit = commit_first_candidate_in_session(&mut session, "jintiantianqi");

    assert_eq!(commit.commit_text, "今天天气");
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 1);
    assert_eq!(session.context_tokens, vec!["今天", "天气"]);
    assert_eq!(
        session.context_tokens.last().map(String::as_str),
        Some("天气")
    );
    let first_weight = user_lexicon
        .transition_snapshot()
        .expect("transition snapshot")
        .get("今天")
        .and_then(|entries| entries.get("天气"))
        .copied()
        .expect("learned transition exists");
    assert!((first_weight - 1.0).abs() < 0.001);

    let second_commit = commit_first_candidate_in_session(&mut session, "jintiantianqi");
    assert_eq!(second_commit.commit_text, "今天天气");
    let second_weight = user_lexicon
        .transition_snapshot()
        .expect("updated transition snapshot")
        .get("今天")
        .and_then(|entries| entries.get("天气"))
        .copied()
        .expect("updated transition exists");
    assert!((second_weight - 2.0).abs() < 0.001);
}

#[test]
fn sequential_candidate_commits_learn_short_phrase_prediction() {
    let temp_db = TempDb::new("learn_short_phrase");
    let settings = settings_with_user_lexicon(temp_db.path.clone());
    let engine = ImeEngine::with_settings(settings.clone()).expect("engine opens user lexicon");
    let mut session = engine.create_session();

    let first = commit_first_candidate_in_session(&mut session, "jintian");
    let second = commit_first_candidate_in_session(&mut session, "tianqi");
    let third = commit_first_candidate_in_session(&mut session, "bucuo");

    assert_eq!(first.commit_text, "今天");
    assert_eq!(second.commit_text, "天气");
    assert_eq!(third.commit_text, "不错");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 2);
    assert_eq!(user_lexicon.trigram_count().expect("trigram count"), 1);
    assert_eq!(
        user_lexicon
            .short_phrase_count()
            .expect("short phrase count"),
        1
    );

    let next_engine = ImeEngine::with_settings(settings).expect("engine reopens user lexicon");
    let mut next_session = next_engine.create_session();
    let output = commit_first_candidate_in_session(&mut next_session, "jintian");

    assert_eq!(output.commit_text, "今天");
    assert_eq!(
        output
            .candidates
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("天气不错")
    );
    assert_eq!(
        next_session
            .feed_key(KeyEvent::from_char('1'))
            .commit_text
            .as_str(),
        "天气不错"
    );
}

#[test]
fn trigram_prediction_uses_two_token_context_before_bigram_fallback() {
    let temp_db = TempDb::new("trigram_context");
    let user_lexicon = Arc::new(UserLexicon::open(&temp_db.path).expect("user lexicon opens"));
    user_lexicon
        .record_transition("天气", "很好", "hen hao")
        .expect("bigram records");
    user_lexicon
        .record_trigram("今天", "天气", "不错", "bu cuo")
        .expect("today trigram records");
    user_lexicon
        .record_trigram("昨天", "天气", "很冷", "hen leng")
        .expect("yesterday trigram records");

    let lexicon = Arc::new(Lexicon::from_tsv("你好\tni hao\t1\n").expect("lexicon loads"));
    let predictor =
        Arc::new(Predictor::from_tsv("left\tright\tfrequency\n").expect("empty predictor loads"));
    let mut session = InputSession::new(
        lexicon,
        predictor,
        Some(user_lexicon),
        ImeSettings::default(),
    );

    session.context_tokens = vec!["今天".to_owned(), "天气".to_owned()];
    assert_eq!(
        session
            .predict_next()
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("不错")
    );

    session.context_tokens = vec!["昨天".to_owned(), "天气".to_owned()];
    assert_eq!(
        session
            .predict_next()
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("很冷")
    );
}

#[test]
fn inactive_trigram_weight_decays_below_recent_learning() {
    let temp_db = TempDb::new("trigram_decay");
    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon opens");
    let connection = Connection::open(&temp_db.path).expect("open raw sqlite connection");
    let one_year_ms = 365_i64 * 24 * 60 * 60 * 1_000;

    connection
        .execute(
            "INSERT INTO user_trigrams
               (first_phrase, second_phrase, next_phrase, next_pinyin, frequency, weight, updated_at_ms)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                "今天",
                "天气",
                "旧候选",
                "jiu hou xuan",
                128_i64,
                128.0_f64,
                current_time_ms().saturating_sub(one_year_ms)
            ],
        )
        .expect("insert inactive trigram");
    user_lexicon
        .record_trigram("今天", "天气", "新候选", "xin hou xuan")
        .expect("record recent trigram");

    assert_eq!(
        user_lexicon
            .predict_trigram("今天", "天气")
            .expect("predict trigram")
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("新候选")
    );
}

#[test]
fn reusing_inactive_trigram_does_not_restore_its_raw_lifetime_count() {
    let temp_db = TempDb::new("trigram_decay_update");
    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon opens");
    let connection = Connection::open(&temp_db.path).expect("open raw sqlite connection");
    let one_year_ms = 365_i64 * 24 * 60 * 60 * 1_000;

    connection
        .execute(
            "INSERT INTO user_trigrams
               (first_phrase, second_phrase, next_phrase, next_pinyin, frequency, weight, updated_at_ms)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                "今天",
                "天气",
                "旧候选",
                "jiu hou xuan",
                128_i64,
                128.0_f64,
                current_time_ms().saturating_sub(one_year_ms)
            ],
        )
        .expect("insert inactive trigram");

    user_lexicon
        .record_trigram("今天", "天气", "旧候选", "jiu hou xuan")
        .expect("reuse inactive trigram");
    let stored_weight: f64 = connection
        .query_row(
            "SELECT weight FROM user_trigrams WHERE next_phrase = '旧候选'",
            [],
            |row| row.get(0),
        )
        .expect("query updated weight");

    assert!(stored_weight > 1.0);
    assert!(stored_weight < 1.1);
}

#[test]
fn concurrent_trigram_learning_keeps_every_local_update() {
    let temp_db = TempDb::new("trigram_concurrent");
    drop(UserLexicon::open(&temp_db.path).expect("initialize user lexicon"));
    let worker_count = 4;
    let writes_per_worker = 20;
    let barrier = Arc::new(Barrier::new(worker_count));
    let mut workers = Vec::new();

    for _ in 0..worker_count {
        let db_path = temp_db.path.clone();
        let barrier = barrier.clone();
        workers.push(std::thread::spawn(move || {
            let user_lexicon = UserLexicon::open(db_path).expect("worker opens user lexicon");
            barrier.wait();
            for _ in 0..writes_per_worker {
                user_lexicon
                    .record_trigram("今天", "天气", "不错", "bu cuo")
                    .expect("concurrent trigram records");
            }
        }));
    }
    for worker in workers {
        worker.join().expect("worker completes");
    }

    let connection = Connection::open(&temp_db.path).expect("open raw sqlite connection");
    let (frequency, weight): (i64, f64) = connection
        .query_row(
            "SELECT frequency, weight FROM user_trigrams
             WHERE first_phrase = '今天' AND second_phrase = '天气' AND next_phrase = '不错'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("query concurrent trigram");

    let expected_writes =
        i64::try_from(worker_count * writes_per_worker).expect("write count fits i64");
    assert_eq!(frequency, expected_writes);
    assert!(weight > expected_writes as f64 - 0.01);
    assert!(weight <= expected_writes as f64);
}

#[test]
fn user_learning_capacity_evicts_low_weight_old_rows() {
    let temp_db = TempDb::new("learning_capacity");
    let limits = UserLearningLimits {
        phrases: 2,
        bigrams: 2,
        short_phrases: 2,
        trigrams: 2,
    };
    let user_lexicon =
        UserLexicon::open_with_limits(&temp_db.path, limits).expect("user lexicon opens");

    user_lexicon
        .record_selection("保留", "bao liu")
        .expect("record favored phrase");
    user_lexicon
        .record_selection("保留", "bao liu")
        .expect("reinforce favored phrase");
    user_lexicon
        .record_selection("较旧", "jiao jiu")
        .expect("record older phrase");
    user_lexicon
        .record_selection("最新", "zui xin")
        .expect("record newest phrase");

    for index in 0..3 {
        user_lexicon
            .record_transition("左", &format!("右{index}"), "you")
            .expect("record bigram");
        user_lexicon
            .record_short_phrase_prediction("左", &format!("短句{index}"), 2)
            .expect("record short phrase");
        user_lexicon
            .record_trigram("甲", "乙", &format!("丙{index}"), "bing")
            .expect("record trigram");
    }

    assert_eq!(user_lexicon.entry_count().expect("phrase count"), 2);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 2);
    assert_eq!(
        user_lexicon
            .short_phrase_count()
            .expect("short phrase count"),
        2
    );
    assert_eq!(user_lexicon.trigram_count().expect("trigram count"), 2);

    let connection = Connection::open(&temp_db.path).expect("open raw sqlite connection");
    let favored_count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM user_phrases WHERE phrase = '保留'",
            [],
            |row| row.get(0),
        )
        .expect("query retained phrase");
    assert_eq!(favored_count, 1);
}

#[test]
fn session_context_is_bounded_for_long_running_hosts() {
    let engine = ImeEngine::new().expect("engine loads");
    let mut session = engine.create_session();

    for _ in 0..(MAX_CONTEXT_TOKENS + 4) {
        commit_first_candidate_in_session(&mut session, "nihao");
    }

    assert_eq!(session.context_tokens.len(), MAX_CONTEXT_TOKENS);
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
    assert_eq!(user_lexicon.trigram_count().expect("trigram count"), 0);
}

#[test]
fn disabled_user_learning_does_not_write_short_phrase_prediction() {
    let temp_db = TempDb::new("short_phrase_disabled");
    let mut settings = settings_with_user_lexicon(temp_db.path.clone());
    settings.enable_user_learning = false;
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");
    let mut session = engine.create_session();

    commit_first_candidate_in_session(&mut session, "jintian");
    commit_first_candidate_in_session(&mut session, "tianqi");
    commit_first_candidate_in_session(&mut session, "bucuo");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 0);
    assert_eq!(user_lexicon.trigram_count().expect("trigram count"), 0);
    assert_eq!(
        user_lexicon
            .short_phrase_count()
            .expect("short phrase count"),
        0
    );
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
    assert_eq!(user_lexicon.trigram_count().expect("trigram count"), 0);
}

#[test]
fn strict_privacy_mode_does_not_write_short_phrase_prediction() {
    let temp_db = TempDb::new("strict_short_phrase");
    let mut settings = settings_with_user_lexicon(temp_db.path.clone());
    settings.strict_privacy_mode = true;
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");
    let mut session = engine.create_session();

    commit_first_candidate_in_session(&mut session, "jintian");
    commit_first_candidate_in_session(&mut session, "tianqi");
    commit_first_candidate_in_session(&mut session, "bucuo");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 0);
    assert_eq!(user_lexicon.trigram_count().expect("trigram count"), 0);
    assert_eq!(
        user_lexicon
            .short_phrase_count()
            .expect("short phrase count"),
        0
    );
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
fn clear_user_lexicon_removes_short_phrase_predictions() {
    let temp_db = TempDb::new("clear_short_phrase");
    let temp_export = TempFile::new("clear_short_phrase", "tsv");
    let settings = settings_with_user_lexicon(temp_db.path.clone());
    let engine = ImeEngine::with_settings(settings).expect("engine opens user lexicon");
    let mut session = engine.create_session();

    commit_first_candidate_in_session(&mut session, "jintian");
    commit_first_candidate_in_session(&mut session, "tianqi");
    commit_first_candidate_in_session(&mut session, "bucuo");

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon reopens");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 3);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 2);
    assert_eq!(user_lexicon.trigram_count().expect("trigram count"), 1);
    assert_eq!(
        user_lexicon
            .short_phrase_count()
            .expect("short phrase count"),
        1
    );
    assert_eq!(
        engine
            .export_user_lexicon(&temp_export.path)
            .expect("export lexicon"),
        7
    );
    let exported = std::fs::read_to_string(&temp_export.path).expect("read export");
    assert!(exported.contains("# user_short_phrases"));
    assert!(exported.contains("left_phrase\tphrase\ttoken_count\tfrequency\tupdated_at_ms"));
    assert!(exported.contains("今天\t天气不错\t2\t1\t"));
    assert!(exported.contains("# user_trigrams"));
    assert!(exported.contains(
        "first_phrase\tsecond_phrase\tnext_phrase\tnext_pinyin\tfrequency\tupdated_at_ms"
    ));
    assert!(exported.contains("今天\t天气\t不错\tbu cuo\t1\t"));

    engine.clear_user_lexicon().expect("clear lexicon");
    assert_eq!(user_lexicon.entry_count().expect("entry count"), 0);
    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 0);
    assert_eq!(user_lexicon.trigram_count().expect("trigram count"), 0);
    assert_eq!(
        user_lexicon
            .short_phrase_count()
            .expect("short phrase count"),
        0
    );
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
fn user_bigram_learning_skips_empty_pinyin() {
    let temp_db = TempDb::new("empty_pinyin_bigram");
    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon opens");

    user_lexicon
        .record_transition("今天", "天气不错", "")
        .expect("record empty-pinyin transition is ignored");

    assert_eq!(user_lexicon.bigram_count().expect("bigram count"), 0);
}

#[test]
fn user_short_phrase_learning_skips_long_phrases() {
    let temp_db = TempDb::new("long_short_phrase");
    let user_lexicon = UserLexicon::open(&temp_db.path).expect("user lexicon opens");

    user_lexicon
        .record_short_phrase_prediction("今天", "一二三四五六七八九十十一二", 2)
        .expect("record long short phrase is ignored");

    assert_eq!(
        user_lexicon
            .short_phrase_count()
            .expect("short phrase count"),
        0
    );
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
fn existing_user_learning_tables_migrate_frequency_into_decay_weight() {
    let temp_db = TempDb::new("decay_weight_migration");
    let connection = Connection::open(&temp_db.path).expect("open raw sqlite connection");
    connection
        .execute_batch(
            "CREATE TABLE user_bigrams (
               left_phrase TEXT NOT NULL,
               right_phrase TEXT NOT NULL,
               right_pinyin TEXT NOT NULL,
               frequency INTEGER NOT NULL,
               updated_at_ms INTEGER NOT NULL,
               PRIMARY KEY (left_phrase, right_phrase)
             );
             INSERT INTO user_bigrams
               (left_phrase, right_phrase, right_pinyin, frequency, updated_at_ms)
             VALUES ('今天', '天气', 'tian qi', 7, 1);",
        )
        .expect("create legacy schema");
    drop(connection);

    let _user_lexicon = UserLexicon::open(&temp_db.path).expect("migrate user lexicon");
    let connection = Connection::open(&temp_db.path).expect("reopen raw sqlite connection");
    let weight: f64 = connection
        .query_row(
            "SELECT weight FROM user_bigrams WHERE left_phrase = '今天'",
            [],
            |row| row.get(0),
        )
        .expect("query migrated weight");

    assert_eq!(weight, 7.0);
}

#[test]
fn existing_user_phrases_migrate_nine_key_signatures() {
    let temp_db = TempDb::new("nine_key_migration");
    let connection = Connection::open(&temp_db.path).expect("open raw sqlite connection");
    connection
        .execute_batch(
            "CREATE TABLE user_phrases (
               phrase TEXT NOT NULL,
               pinyin TEXT NOT NULL,
               compact_pinyin TEXT NOT NULL,
               frequency INTEGER NOT NULL,
               weight REAL NOT NULL DEFAULT 1.0,
               updated_at_ms INTEGER NOT NULL,
               PRIMARY KEY (phrase, pinyin)
             );
             INSERT INTO user_phrases
               (phrase, pinyin, compact_pinyin, frequency, weight, updated_at_ms)
             VALUES ('你好', 'ni hao', 'nihao', 2, 2.0, 1);",
        )
        .expect("create legacy phrase schema");
    drop(connection);

    let user_lexicon = UserLexicon::open(&temp_db.path).expect("migrate user lexicon");
    assert_eq!(
        user_lexicon
            .lookup_nine_key("64426")
            .expect("lookup migrated candidate")
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("你好")
    );

    drop(user_lexicon);
    let reopened = UserLexicon::open(&temp_db.path).expect("repeat migration is idempotent");
    assert_eq!(
        reopened
            .lookup_nine_key("64426")
            .expect("lookup candidate after repeated migration")
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("你好")
    );
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
