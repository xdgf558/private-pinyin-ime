use std::sync::Arc;

use ime_core::lexicon::Lexicon;
use ime_core::predictor::Predictor;
use ime_core::session::MAX_RAW_INPUT_CHARS;
use ime_core::{ImeEngine, ImeSettings, InputSession, KeyCode, KeyEvent, Modifiers};

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
fn starter_lexicon_returns_common_terms() {
    let engine = ImeEngine::new().expect("engine loads starter lexicon");

    for (raw_input, expected) in [
        ("diannao", "电脑"),
        ("shijian", "时间"),
        ("yinwei", "因为"),
        ("wenjian", "文件"),
    ] {
        let candidates = engine.candidates_for_raw(raw_input);
        assert!(
            candidates
                .iter()
                .any(|candidate| candidate.text == expected),
            "{raw_input} should include {expected}"
        );
    }
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
fn unhandled_key_preserves_active_composition_output() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    for ch in "nihao".chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }

    let output = session.feed_key(KeyEvent::new(KeyCode::ArrowDown));

    assert_eq!(session.raw_input, "nihao");
    assert_eq!(output.preedit, "nihao");
    assert!(!output.should_update_preedit);
    assert!(!output.should_commit);
    assert!(output.should_show_candidates);
    assert!(output
        .candidates
        .iter()
        .any(|candidate| candidate.text == "你好"));
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
fn punctuation_after_composition_commits_first_candidate_before_punctuation() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let mut session = engine.create_session();

    for ch in "nihao".chars() {
        session.feed_key(KeyEvent::from_char(ch));
    }
    let output = session.feed_key(KeyEvent::from_char(','));

    assert!(output.should_commit);
    assert_eq!(output.commit_text, "你好,");
    assert_eq!(session.raw_input, "");
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

#[test]
fn candidate_paging_uses_page_size_and_selection_uses_current_page() {
    let mut session = session_with_page_size(
        "A1\ta\t100\nA2\tai\t90\nA3\tan\t80\nA4\tang\t70\nA5\tao\t60\n",
        2,
    );

    let first_page = session.feed_key(KeyEvent::from_char('a'));

    assert_eq!(
        first_page
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        vec!["A1", "A2"]
    );
    assert_eq!(session.candidates.len(), 5);

    let second_page = session.feed_key(KeyEvent::new(KeyCode::PageDown));

    assert_eq!(
        second_page
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        vec!["A3", "A4"]
    );

    let commit = session.feed_key(KeyEvent::from_char('1'));

    assert_eq!(commit.commit_text, "A3");
}

#[test]
fn digit_selection_only_uses_visible_candidate_page() {
    let mut session = session_with_page_size(
        "A1\ta\t100\nA2\tai\t90\nA3\tan\t80\nA4\tang\t70\nA5\tao\t60\nA6\tan a\t50\nA7\tang a\t40\n",
        5,
    );

    let first_page = session.feed_key(KeyEvent::from_char('a'));

    assert_eq!(first_page.candidates.len(), 5);
    assert_eq!(session.candidates.len(), 7);

    let output = session.feed_key(KeyEvent::from_char('7'));

    assert!(!output.should_commit);
    assert_eq!(output.commit_text, "");
    assert_eq!(session.raw_input, "a");
    assert_eq!(
        output
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        vec!["A1", "A2", "A3", "A4", "A5"]
    );
}

fn session_with_page_size(tsv: &str, candidate_page_size: usize) -> InputSession {
    InputSession::new(
        Arc::new(Lexicon::from_tsv(tsv).expect("test lexicon loads")),
        Arc::new(Predictor::from_tsv("left\tright\tfrequency\n").expect("empty predictor loads")),
        None,
        ImeSettings {
            candidate_page_size,
            ..ImeSettings::default()
        },
    )
}
