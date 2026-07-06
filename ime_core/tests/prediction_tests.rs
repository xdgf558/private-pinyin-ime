use ime_core::ImeEngine;
use ime_core::KeyEvent;

#[test]
fn stage_one_prediction_is_not_enabled_yet() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let session = engine.create_session();

    assert!(session.predict_next().is_empty());
}

#[test]
fn committing_jintian_predicts_tianqi() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    for ch in "jintian".chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }
    let output = session.feed_key(KeyEvent::from_char(' '));

    assert_eq!(output.commit_text, "今天");
    assert_eq!(session.raw_input, "");
    assert!(output
        .candidates
        .iter()
        .any(|candidate| candidate.text == "天气"));
}

#[test]
fn prediction_candidates_do_not_hijack_idle_space() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    for ch in "jintian".chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }
    session.feed_key(KeyEvent::from_char(' '));
    let output = session.feed_key(KeyEvent::from_char(' '));

    assert_eq!(output.commit_text, " ");
    assert!(session.candidates.is_empty());
}

#[test]
fn prediction_candidates_can_be_selected_with_digit() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    for ch in "jintian".chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }
    session.feed_key(KeyEvent::from_char(' '));
    let output = session.feed_key(KeyEvent::from_char('1'));

    assert_eq!(output.commit_text, "天气");
}
