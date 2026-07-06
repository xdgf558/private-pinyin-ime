use ime_core::PinyinParser;

fn parse_strings(raw_input: &str) -> Vec<String> {
    PinyinParser
        .parse(raw_input)
        .into_iter()
        .map(|parse| parse.pinyin_string())
        .collect()
}

#[test]
fn parses_basic_complete_pinyin() {
    assert!(parse_strings("nihao").contains(&"ni hao".to_owned()));
    assert!(parse_strings("zhongguo").contains(&"zhong guo".to_owned()));
}

#[test]
fn parses_ambiguous_xian() {
    let parses = parse_strings("xian");
    assert!(parses.contains(&"xian".to_owned()));
    assert!(parses.contains(&"xi an".to_owned()));
}

#[test]
fn apostrophe_forces_syllable_boundary() {
    let parses = parse_strings("xi'an");
    assert_eq!(parses.first(), Some(&"xi an".to_owned()));
}

#[test]
fn normalizes_v_to_umlaut() {
    assert!(parse_strings("lvshi").contains(&"lü shi".to_owned()));
    assert!(parse_strings("nver").contains(&"nü er".to_owned()));
}

#[test]
fn supports_partial_last_syllable() {
    let parses = PinyinParser.parse("zhongg");
    assert!(parses.iter().any(|parse| {
        parse.pinyin_string() == "zhong g" && parse.syllables.last().is_some_and(|s| s.is_prefix)
    }));
}
