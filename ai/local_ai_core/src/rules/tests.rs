use crate::{AiErrorCode, AiPrivacyMode};

use super::{
    EnglishTermPreserver, LexiconCleanupAnalyzer, LexiconCleanupReasonCode, MixedInputSegmentKind,
    PinyinCorrectionReason, PinyinCorrector, UserLexiconSnapshotEntry, MAX_MIXED_INPUT_BYTES,
    MAX_PINYIN_CORRECTIONS,
};

const DAY_MS: i64 = 24 * 60 * 60 * 1_000;

#[test]
fn correction_rules_cover_common_confusion_duplicate_and_missing_medial() {
    let corrector = PinyinCorrector::embedded();

    let zongguo = corrector.suggest("zongguo");
    assert_eq!(zongguo[0].corrected_pinyin(), "zhongguo");
    assert_eq!(zongguo[0].reason(), PinyinCorrectionReason::CommonConfusion);

    let jinntian = corrector.suggest("jinntian");
    assert_eq!(jinntian[0].corrected_pinyin(), "jintian");
    assert_eq!(
        jinntian[0].reason(),
        PinyinCorrectionReason::DuplicateLetter
    );

    let nhao = corrector.suggest("nhao");
    assert_eq!(nhao[0].corrected_pinyin(), "nihao");
    assert_eq!(nhao[0].reason(), PinyinCorrectionReason::MissingMedial);
}

#[test]
fn correction_never_replaces_normal_input_and_is_bounded() {
    let corrector = PinyinCorrector::embedded();

    assert!(corrector.suggest("zhongguo").is_empty());
    assert!(corrector.suggest("nihao").is_empty());
    assert!(corrector.suggest("GitHub").is_empty());
    assert!(corrector.suggest("123456").is_empty());
    assert!(corrector.suggest("jinntiannhao").len() <= MAX_PINYIN_CORRECTIONS);
}

#[test]
fn correction_validator_discards_unresolvable_suggestions() {
    let suggestions = PinyinCorrector::embedded()
        .suggest_with_validator("zongguo", |corrected| corrected == "something-else");

    assert!(suggestions.is_empty());
}

#[test]
fn correction_debug_output_redacts_pinyin() {
    let suggestion = PinyinCorrector::embedded().suggest("zongguo").remove(0);
    let debug = format!("{suggestion:?}");

    assert!(!debug.contains("zhongguo"));
    assert!(debug.contains("<redacted>"));
}

#[test]
fn english_terms_preserve_case_and_longest_phrase() {
    let preserver = EnglishTermPreserver::embedded();
    let segmentation = preserver
        .segment("zhegeapikeybiefashangqu")
        .expect("mixed input segmentation");
    let segments = segmentation.segments();

    assert_eq!(segments.len(), 3);
    assert_eq!(segments[0].kind(), MixedInputSegmentKind::Pinyin);
    assert_eq!(segments[0].value(), "zhege");
    assert_eq!(segments[1].kind(), MixedInputSegmentKind::EnglishTerm);
    assert_eq!(segments[1].value(), "API key");
    assert_eq!(segments[2].value(), "biefashangqu");

    let rendered = segmentation
        .render_with(|pinyin| match pinyin {
            "zhege" => Some("这个".to_owned()),
            "biefashangqu" => Some("别发上去".to_owned()),
            _ => None,
        })
        .expect("all pinyin segments decode");
    assert_eq!(rendered, "这个 API key 别发上去");
}

#[test]
fn multiple_english_terms_render_without_changing_canonical_case() {
    let segmentation = EnglishTermPreserver::embedded()
        .segment("wozaigithubkanpr")
        .expect("mixed input segmentation");
    let rendered = segmentation
        .render_with(|pinyin| match pinyin {
            "wozai" => Some("我在".to_owned()),
            "kan" => Some("看".to_owned()),
            _ => None,
        })
        .expect("all pinyin segments decode");

    assert_eq!(rendered, "我在 GitHub 看 PR");
}

#[test]
fn english_term_boundaries_require_surrounding_pinyin_to_decode() {
    let preserver = EnglishTermPreserver::embedded();
    let valid = preserver
        .segment("wozaigithub")
        .and_then(|segments| {
            segments.render_with(|pinyin| (pinyin == "wozai").then(|| "我在".to_owned()))
        })
        .expect("known surrounding pinyin renders");
    assert_eq!(valid, "我在 GitHub");

    let unresolved = preserver
        .segment("githubxxx")
        .expect("term segmentation remains observable")
        .render_with(|_| None);
    assert!(
        unresolved.is_none(),
        "unknown boundary text must reject the mixed candidate"
    );
}

#[test]
fn english_term_segmentation_rejects_overlong_or_non_ascii_input() {
    let preserver = EnglishTermPreserver::embedded();
    let overlong = format!("{}github", "a".repeat(MAX_MIXED_INPUT_BYTES));

    assert!(preserver.segment(&overlong).is_none());
    assert!(preserver.segment("我用github").is_none());
}

#[test]
fn mixed_segmentation_debug_output_redacts_content() {
    let segmentation = EnglishTermPreserver::embedded()
        .segment("woyongcodexxiedaima")
        .expect("mixed input segmentation");
    let segment_debug = format!("{:?}", segmentation.segments()[1]);
    let segmentation_debug = format!("{segmentation:?}");

    assert!(!segment_debug.contains("Codex"));
    assert!(!segmentation_debug.contains("woyong"));
}

#[test]
fn cleanup_suggestions_are_read_only_and_use_reason_codes() {
    let now = 300 * DAY_MS;
    let entries = vec![
        UserLexiconSnapshotEntry::new("GitHub", "github", 9, now - DAY_MS)
            .as_user_english_term(true),
        UserLexiconSnapshotEntry::new(" github ", "git hub", 1, now - 2 * DAY_MS)
            .as_user_english_term(true),
        UserLexiconSnapshotEntry::new("旧词", "jiu ci", 1, now - 200 * DAY_MS),
        UserLexiconSnapshotEntry::new("错误!术语", "invalid", 3, now - DAY_MS)
            .as_user_english_term(true),
    ];
    let original = entries.clone();

    let suggestions = LexiconCleanupAnalyzer
        .suggest(&entries, now, AiPrivacyMode::Standard)
        .expect("standard cleanup suggestions");

    assert_eq!(entries, original, "analysis must never mutate the snapshot");
    assert!(suggestions.iter().any(|suggestion| {
        suggestion.entry_index() == 1
            && suggestion.reason_code() == LexiconCleanupReasonCode::DuplicateNormalizedEntry
    }));
    assert!(suggestions.iter().any(|suggestion| {
        suggestion.entry_index() == 2
            && suggestion.reason_code() == LexiconCleanupReasonCode::StaleLowFrequency
    }));
    assert!(suggestions.iter().any(|suggestion| {
        suggestion.entry_index() == 3
            && suggestion.reason_code() == LexiconCleanupReasonCode::InvalidEnglishTerm
    }));
}

#[test]
fn cleanup_is_disabled_in_strict_privacy_mode() {
    let entries = vec![UserLexiconSnapshotEntry::new("旧词", "jiu ci", 1, 0)];
    let error = LexiconCleanupAnalyzer
        .suggest(&entries, 365 * DAY_MS, AiPrivacyMode::Strict)
        .expect_err("strict privacy must disable lexicon inspection");

    assert_eq!(error.code(), AiErrorCode::Disabled);
}

#[test]
fn lexicon_snapshot_debug_output_redacts_user_content() {
    let entry = UserLexiconSnapshotEntry::new("私人词", "si ren ci", 2, 10);
    let debug = format!("{entry:?}");

    assert!(!debug.contains("私人词"));
    assert!(!debug.contains("si ren ci"));
    assert!(debug.contains("<redacted>"));
}
