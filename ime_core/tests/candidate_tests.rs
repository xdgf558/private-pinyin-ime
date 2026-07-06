use ime_core::session::MAX_RAW_INPUT_CHARS;
use ime_core::{ImeEngine, KeyCode, KeyEvent, Modifiers};

#[test]
fn nihao_returns_expected_candidates() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let candidates = engine.candidates_for_raw("nihao");

    assert!(candidates.iter().any(|candidate| candidate.text == "你好"));
    assert!(candidates.iter().any(|candidate| candidate.text == "你号"));
}

#[test]
fn continuous_pinyin_returns_phrase_candidate() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let candidates = engine.candidates_for_raw("woxiangqu");

    assert!(candidates
        .iter()
        .any(|candidate| candidate.text == "我想去"));
}

#[test]
fn input_session_updates_preedit_and_commits_first_candidate_with_space() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();
    let mut output = session.feed_key(KeyEvent::from_char('n'));

    for ch in "ihao".chars() {
        output = session.feed_key(KeyEvent::from_char(ch));
    }

    assert_eq!(output.preedit, "nihao");
    assert!(output.should_show_candidates);
    assert!(output
        .candidates
        .iter()
        .any(|candidate| candidate.text == "你好"));

    let commit = session.feed_key(KeyEvent::from_char(' '));
    assert!(commit.should_commit);
    assert_eq!(commit.commit_text, "你好");
    assert_eq!(session.raw_input, "");
}

#[test]
fn enter_commits_raw_input() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    for ch in "abc".chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }

    let output = session.feed_key(KeyEvent::from_char('\n'));
    assert_eq!(output.commit_text, "abc");
}

#[test]
fn enter_is_idle_without_raw_input() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    let output = session.feed_key(KeyEvent::from_char('\n'));

    assert!(!output.should_commit);
    assert_eq!(output.commit_text, "");
}

#[test]
fn raw_input_is_capped() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    for _ in 0..(MAX_RAW_INPUT_CHARS + 10) {
        session.feed_key(KeyEvent::from_char('a'));
    }

    assert_eq!(session.raw_input.chars().count(), MAX_RAW_INPUT_CHARS);
}

#[test]
fn system_modifier_key_does_not_enter_composition() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    session.feed_key(KeyEvent::from_char('n'));
    session.feed_key(KeyEvent::from_char('i'));
    let output = session.feed_key(KeyEvent {
        key_code: KeyCode::Character('c'),
        text: "c".to_owned(),
        modifiers: Modifiers {
            ctrl: true,
            ..Modifiers::default()
        },
        is_repeat: false,
        timestamp_ms: 0,
    });

    assert_eq!(session.raw_input, "ni");
    assert!(!output.should_commit);
}

#[test]
fn punctuation_commits_in_chinese_mode() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    let output = session.feed_key(KeyEvent::from_char('.'));

    assert!(output.should_commit);
    assert_eq!(output.commit_text, ".");
}

#[test]
fn space_commits_raw_input_when_no_candidate_exists() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    for ch in "abc".chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }

    let output = session.feed_key(KeyEvent::from_char(' '));

    assert!(output.should_commit);
    assert_eq!(output.commit_text, "abc");
}
