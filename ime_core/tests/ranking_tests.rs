use ime_core::ImeEngine;

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
fn prefix_match_has_lower_score_than_exact_match() {
    let engine = ImeEngine::new().expect("engine loads sample lexicon");
    let exact_score = engine
        .candidates_for_raw("zhongguo")
        .into_iter()
        .find(|candidate| candidate.text == "中国")
        .expect("exact candidate exists")
        .score;
    let prefix_score = engine
        .candidates_for_raw("zhongg")
        .into_iter()
        .find(|candidate| candidate.text == "中国")
        .expect("prefix candidate exists")
        .score;

    assert!(exact_score > prefix_score);
}
