use std::sync::Arc;
use std::time::{Duration, Instant};

use ime_core::lexicon::Lexicon;
use ime_core::predictor::Predictor;
use ime_core::ranker::Ranker;
use ime_core::session::MAX_RAW_INPUT_CHARS;
use ime_core::{
    pinyin_to_nine_key, ImeEngine, ImeSettings, InputSession, KeyCode, KeyEvent, Modifiers,
    PinyinParser,
};

#[test]
fn nihao_returns_expected_candidates() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let candidates = engine.candidates_for_raw("nihao");

    assert_eq!(
        candidates.first().map(|candidate| candidate.text.as_str()),
        Some("你好")
    );
    assert!(candidates
        .iter()
        .any(|candidate| candidate.text == "你好啊"));
}

#[test]
fn nine_key_nihao_returns_expected_candidate() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let candidates = engine.candidates_for_nine_key("64426");

    assert_eq!(
        candidates.first().map(|candidate| candidate.text.as_str()),
        Some("你好")
    );
}

#[test]
fn nine_key_continuous_input_segments_common_sentence() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let digits = pinyin_to_nine_key("wo jin tian xiang qu chi fan");
    let candidates = engine.candidates_for_nine_key(&digits);

    assert!(candidates
        .iter()
        .any(|candidate| candidate.text == "我今天想去吃饭"));
}

#[test]
fn nine_key_session_commits_candidate_and_supports_backspace() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let mut session = engine.create_session();
    let mut output = session.feed_key(KeyEvent::new(KeyCode::NineKeyDigit(6)));
    for digit in [4, 4, 2, 6] {
        output = session.feed_key(KeyEvent::new(KeyCode::NineKeyDigit(digit)));
    }

    assert_eq!(output.preedit, "64426");
    assert_eq!(
        output
            .candidates
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("你好")
    );

    let shortened = session.feed_key(KeyEvent::new(KeyCode::Backspace));
    assert_eq!(shortened.preedit, "6442");
    let restored = session.feed_key(KeyEvent::new(KeyCode::NineKeyDigit(6)));
    assert_eq!(restored.preedit, "64426");

    let commit = session.feed_key(KeyEvent::new(KeyCode::Space));
    assert_eq!(commit.commit_text, "你好");
    assert!(session.nine_key_input.is_empty());
}

#[test]
fn continuous_pinyin_returns_phrase_candidate() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let candidates = engine.candidates_for_raw("xiangqu");

    assert!(candidates.iter().any(|candidate| candidate.text == "想去"));
}

#[test]
fn long_continuous_pinyin_can_segment_common_sentence() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let candidates = engine.candidates_for_raw("wojintianxiangquchifan");

    assert!(candidates
        .iter()
        .any(|candidate| candidate.text == "我今天想去吃饭"));
}

#[test]
fn joint_decoder_uses_bigram_context_to_resolve_ambiguous_boundaries() {
    let lexicon = Lexicon::from_tsv(
        "今天\tjin tian\t1000\n天气\ttian qi\t1000\n今\tjin\t100000\n天天\ttian tian\t100000\n期\tqi\t100000\n",
    )
    .expect("test lexicon loads");
    let predictor = Predictor::from_tsv("今天\t天气\t1000000\n").expect("bigram loads");
    let raw_input = "jintiantianqi";
    let parses = PinyinParser.parse(raw_input);
    let candidates = lexicon.lookup_with_context(raw_input, &parses, None, |left, right| {
        Ranker::score_continuous_transition(predictor.transition_frequency(left, right), 0)
    });

    let first = candidates.first().expect("continuous candidate exists");
    assert_eq!(first.text, "今天天气");
    assert_eq!(
        first
            .segments
            .iter()
            .map(|segment| segment.text.as_str())
            .collect::<Vec<_>>(),
        vec!["今天", "天气"]
    );
}

#[test]
fn joint_decoder_respects_apostrophe_syllable_boundaries() {
    let lexicon = Lexicon::from_tsv("先\txian\t1000000\n西\txi\t100\n安\tan\t100\n好\thao\t100\n")
        .expect("test lexicon loads");
    let raw_input = "xi'anhao";
    let parses = PinyinParser.parse(raw_input);
    let candidates = lexicon.lookup(raw_input, &parses);

    assert_eq!(
        candidates.first().map(|candidate| candidate.text.as_str()),
        Some("西安好")
    );
    assert!(candidates.iter().all(|candidate| candidate.text != "先好"));
}

#[test]
fn second_generation_continuous_pinyin_handles_common_sentences() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");

    for (raw_input, expected) in [
        ("jintiantianqibucuo", "今天天气不错"),
        ("gailvhenxiao", "概率很小"),
        ("wojintianxiangquchifan", "我今天想去吃饭"),
    ] {
        let candidates = engine.candidates_for_raw(raw_input);
        assert_eq!(
            candidates.first().map(|candidate| candidate.text.as_str()),
            Some(expected),
            "{raw_input} should rank {expected} first"
        );
    }
}

#[test]
fn joint_decoder_stays_within_interactive_lookup_budget() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let iterations = 20;
    let started = Instant::now();
    for _ in 0..iterations {
        let candidates = engine.candidates_for_raw("wojintianxiangquchifan");
        assert!(!candidates.is_empty());
    }
    let average = started.elapsed() / iterations;

    assert!(
        average < Duration::from_millis(60),
        "average continuous lookup took {average:?}"
    );
}

#[test]
fn nine_key_decoder_stays_within_interactive_lookup_budget() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let digits = pinyin_to_nine_key("wo jin tian xiang qu chi fan");
    let iterations = 20;
    let started = Instant::now();
    for _ in 0..iterations {
        let candidates = engine.candidates_for_nine_key(&digits);
        assert!(!candidates.is_empty());
    }
    let average = started.elapsed() / iterations;

    assert!(
        average < Duration::from_millis(60),
        "average nine-key continuous lookup took {average:?}"
    );
}

#[test]
fn shorthand_initials_return_phrase_candidates() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let candidates = engine.candidates_for_raw("nh");

    assert!(candidates.iter().any(|candidate| candidate.text == "你好"));
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
fn production_lexicon_returns_ganma_phrase() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let candidates = engine.candidates_for_raw("ganma");

    assert_eq!(
        candidates.first().map(|candidate| candidate.text.as_str()),
        Some("干嘛")
    );
}

#[test]
fn production_lexicon_prioritizes_common_lv_words() {
    let engine = ImeEngine::new().expect("engine loads production lexicon");
    let lv_candidates = engine.candidates_for_raw("lv");
    let gailv_candidates = engine.candidates_for_raw("gailv");

    assert!(lv_candidates
        .iter()
        .take(3)
        .any(|candidate| candidate.text == "率"));
    assert_eq!(
        gailv_candidates
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("概率")
    );
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

    let output = session.feed_key(KeyEvent::new(KeyCode::Unknown));

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
    assert_eq!(output.commit_text, "。");
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
    assert_eq!(output.commit_text, "你好，");
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
