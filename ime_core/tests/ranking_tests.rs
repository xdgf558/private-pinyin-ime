use ime_core::lexicon::Lexicon;
use ime_core::{ImeEngine, PinyinParser};

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
