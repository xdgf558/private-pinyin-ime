use std::sync::Arc;

use ime_core::lexicon::Lexicon;
use ime_core::predictor::Predictor;
use ime_core::{ImeMode, ImeSettings, InputSession, KeyCode, KeyEvent};

fn session_with_candidates(candidate_page_size: usize) -> InputSession {
    InputSession::new(
        Arc::new(
            Lexicon::from_tsv(
                "甲\ta\t100\n乙\tai\t90\n丙\tan\t80\n丁\tang\t70\n戊\tao\t60\n己\ta a\t50\n庚\ta ai\t40\n辛\ta an\t30\n壬\ta ang\t20\n",
            )
            .expect("blind-typing fixture lexicon loads"),
        ),
        Arc::new(
            Predictor::from_tsv("left\tright\tfrequency\n")
                .expect("empty predictor fixture loads"),
        ),
        None,
        ImeSettings {
            candidate_page_size,
            ..ImeSettings::default()
        },
    )
}

fn type_text(session: &mut InputSession, input: &str) {
    for character in input.chars() {
        let _ = session.feed_key(KeyEvent::from_char(character));
    }
}

#[test]
fn space_commits_the_visible_default_exactly_once() {
    let mut session = session_with_candidates(5);
    let page = session.feed_key(KeyEvent::from_char('a'));
    let expected = page.candidates[0].text.clone();

    let commit = session.feed_key(KeyEvent::new(KeyCode::Space));
    assert!(commit.should_commit);
    assert_eq!(commit.commit_text, expected);
    assert_eq!(commit.preedit, "");
    assert!(!commit.should_show_candidates);
    assert!(session.current_page_candidates_snapshot().is_empty());

    let following_space = session.feed_key(KeyEvent::new(KeyCode::Space));
    assert_eq!(following_space.commit_text, " ");
}

#[test]
fn numbered_keys_select_only_the_current_visible_page() {
    for number in 1..=9 {
        let mut session = session_with_candidates(9);
        let page = session.feed_key(KeyEvent::from_char('a'));
        let expected = page.candidates[usize::from(number - 1)].text.clone();

        let commit = session.feed_key(KeyEvent::new(KeyCode::Digit(number)));
        assert!(commit.should_commit);
        assert_eq!(commit.commit_text, expected);
        assert!(!commit.should_show_candidates);
    }

    let mut session = session_with_candidates(5);
    let page = session.feed_key(KeyEvent::from_char('a'));
    let expected_ids = page
        .candidates
        .iter()
        .map(|candidate| candidate.id.clone())
        .collect::<Vec<_>>();
    let unavailable = session.feed_key(KeyEvent::new(KeyCode::Digit(6)));
    assert!(!unavailable.should_commit);
    assert_eq!(unavailable.preedit, "a");
    assert_eq!(
        unavailable
            .candidates
            .iter()
            .map(|candidate| candidate.id.clone())
            .collect::<Vec<_>>(),
        expected_ids
    );
}

#[test]
fn paging_then_number_selection_commits_the_displayed_identity() {
    let mut session = session_with_candidates(3);
    let _ = session.feed_key(KeyEvent::from_char('a'));
    let second_page = session.feed_key(KeyEvent::new(KeyCode::PageDown));
    let selected = second_page.candidates[1].clone();

    let commit = session.feed_key(KeyEvent::new(KeyCode::Digit(2)));
    assert_eq!(commit.commit_text, selected.text);
    assert!(!commit.should_show_candidates);
}

#[test]
fn enter_escape_and_backspace_keep_recovery_predictable() {
    let mut raw_session = session_with_candidates(5);
    type_text(&mut raw_session, "abc");
    let raw_commit = raw_session.feed_key(KeyEvent::new(KeyCode::Enter));
    assert_eq!(raw_commit.commit_text, "abc");

    let mut cancelled_session = session_with_candidates(5);
    type_text(&mut cancelled_session, "ai");
    let cancelled = cancelled_session.feed_key(KeyEvent::new(KeyCode::Escape));
    assert!(!cancelled.should_commit);
    assert_eq!(cancelled.preedit, "");
    assert!(!cancelled.should_show_candidates);

    let mut replay_session = session_with_candidates(5);
    type_text(&mut replay_session, "an");
    let expected = replay_session
        .current_page_candidates_snapshot()
        .into_iter()
        .map(|candidate| candidate.id)
        .collect::<Vec<_>>();
    let shortened = replay_session.feed_key(KeyEvent::new(KeyCode::Backspace));
    assert_eq!(shortened.preedit, "a");
    let restored = replay_session.feed_key(KeyEvent::from_char('n'));
    assert_eq!(
        restored
            .candidates
            .into_iter()
            .map(|candidate| candidate.id)
            .collect::<Vec<_>>(),
        expected
    );
}

#[test]
fn punctuation_uses_the_same_default_as_space() {
    let mut space_session = session_with_candidates(5);
    let page = space_session.feed_key(KeyEvent::from_char('a'));
    let expected = page.candidates[0].text.clone();
    let space = space_session.feed_key(KeyEvent::new(KeyCode::Space));
    assert_eq!(space.commit_text, expected);

    let mut punctuation_session = session_with_candidates(5);
    let _ = punctuation_session.feed_key(KeyEvent::from_char('a'));
    let punctuation = punctuation_session.feed_key(KeyEvent::new(KeyCode::Comma));
    assert_eq!(punctuation.commit_text, format!("{expected}，"));
}

#[test]
fn nine_key_space_commits_the_visible_default() {
    let engine = ime_core::ImeEngine::new().expect("production engine loads");
    let mut session = engine.create_session();
    for digit in [6, 4, 4, 2, 6] {
        let _ = session.feed_key(KeyEvent::new(KeyCode::NineKeyDigit(digit)));
    }
    let expected = session.current_page_candidates_snapshot()[0].text.clone();

    let commit = session.feed_key(KeyEvent::new(KeyCode::Space));
    assert_eq!(commit.commit_text, expected);
    assert_eq!(commit.commit_text, "你好");
    assert!(session.nine_key_input.is_empty());
}

#[test]
fn prediction_state_keeps_space_literal_and_number_selection_explicit() {
    let lexicon = Arc::new(
        Lexicon::from_tsv("今天\tjin tian\t100\n").expect("prediction fixture lexicon loads"),
    );
    let predictor = Arc::new(
        Predictor::from_tsv("今天\t天气\t100\n今天\t晚上\t90\n").expect("prediction fixture loads"),
    );
    let settings = ImeSettings {
        candidate_page_size: 5,
        enable_prediction: true,
        ..ImeSettings::default()
    };

    let mut space_session =
        InputSession::new(lexicon.clone(), predictor.clone(), None, settings.clone());
    type_text(&mut space_session, "jintian");
    let committed = space_session.feed_key(KeyEvent::new(KeyCode::Space));
    assert_eq!(committed.commit_text, "今天");
    assert!(committed.should_show_candidates);
    let literal_space = space_session.feed_key(KeyEvent::new(KeyCode::Space));
    assert_eq!(literal_space.commit_text, " ");

    let mut numbered_session = InputSession::new(lexicon, predictor, None, settings);
    type_text(&mut numbered_session, "jintian");
    let committed = numbered_session.feed_key(KeyEvent::new(KeyCode::Space));
    let predicted = committed.candidates[0].text.clone();
    let prediction_commit = numbered_session.feed_key(KeyEvent::new(KeyCode::Digit(1)));
    assert_eq!(prediction_commit.commit_text, predicted);
    assert_eq!(numbered_session.mode(), ImeMode::Chinese);
}
