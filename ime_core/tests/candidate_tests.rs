use ime_core::{ImeEngine, KeyEvent};

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
    let mut output = engine.feed_text("");

    for ch in "nihao".chars() {
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
