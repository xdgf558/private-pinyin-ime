use ime_core::lexicon::Lexicon;
use ime_core::ranker::{CandidateMatchKind, Ranker};
use ime_core::{Candidate, CandidateSource, ImeEngine, PinyinParser};

#[test]
fn higher_frequency_exact_match_ranks_first() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let candidates = engine.candidates_for_raw("nihao");

    assert_eq!(
        candidates.first().map(|candidate| candidate.text.as_str()),
        Some("你好")
    );
}

#[test]
fn exact_matches_rank_before_higher_frequency_prefix_matches() {
    let lexicon = Lexicon::from_tsv("rare exact\tni\t1\nvery common prefix\tnian\t4294967295\n")
        .expect("headerless lexicon loads");
    let parses = PinyinParser.parse("ni");
    let candidates = lexicon.lookup("ni", &parses);

    assert_eq!(
        candidates.first().map(|candidate| candidate.text.as_str()),
        Some("rare exact")
    );
}

#[test]
fn merged_ranking_keeps_exact_base_match_before_high_frequency_user_prefix() {
    let lexicon = Lexicon::from_tsv("base exact\tni\t1\n").expect("lexicon loads");
    let parses = PinyinParser.parse("ni");
    let base_candidates = lexicon.lookup("ni", &parses);
    let user_candidates = vec![Candidate::new("user prefix", "nian", CandidateSource::User)
        .with_score(Ranker::score(u32::MAX))
        .with_rank_score(Ranker::score_match(
            u32::MAX,
            CandidateMatchKind::Prefix,
            CandidateSource::User,
        ))];

    let merged =
        ime_core::lexicon::merge_user_and_base_candidates(user_candidates, base_candidates);

    assert_eq!(
        merged.first().map(|candidate| candidate.text.as_str()),
        Some("base exact")
    );
}
