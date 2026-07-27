use std::collections::HashSet;
use std::fmt;

use crate::candidate::{
    promote_correction_candidates, Candidate, CandidateCorrection, CandidateCorrectionConfidence,
    CandidateCorrectionKind,
};
use crate::pinyin_parser::{compact_pinyin, PinyinParse, PinyinParser};
use crate::settings::FuzzyPinyinSettings;
use crate::syllable::is_legal_syllable;

pub const MAX_TOLERANT_INPUT_CHARS: usize = 24;
pub const MAX_TOLERANT_VARIANTS: usize = 16;
pub const MAX_TOLERANT_CANDIDATES: usize = 2;

#[derive(Clone, PartialEq, Eq)]
pub struct TolerantPinyinVariant {
    lookup_input: String,
}

impl TolerantPinyinVariant {
    pub fn lookup_input(&self) -> &str {
        &self.lookup_input
    }
}

impl fmt::Debug for TolerantPinyinVariant {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TolerantPinyinVariant")
            .field("lookup_input", &"<redacted>")
            .finish()
    }
}

pub fn tolerant_pinyin_variants(
    raw_input: &str,
    parses: &[PinyinParse],
    settings: FuzzyPinyinSettings,
) -> Vec<TolerantPinyinVariant> {
    if !settings.any_enabled()
        || !raw_input.is_ascii()
        || raw_input.chars().count() > MAX_TOLERANT_INPUT_CHARS
    {
        return Vec::new();
    }

    let normalized = PinyinParser::normalize_raw(raw_input);
    if normalized.is_empty() {
        return Vec::new();
    }

    let normalized_compact = normalized.replace('\'', "");
    let mut seen = HashSet::new();
    let mut variants = Vec::new();
    for parse in parses.iter().filter(|parse| parse.is_complete()) {
        let syllables = parse.syllable_texts();
        for syllable_index in 0..syllables.len() {
            for replacement in syllable_alternatives(&syllables[syllable_index], settings) {
                let mut corrected = syllables.clone();
                corrected[syllable_index] = replacement;
                let lookup_input = corrected.join("'");
                if lookup_input.replace('\'', "") == normalized_compact
                    || !seen.insert(lookup_input.clone())
                {
                    continue;
                }
                variants.push(TolerantPinyinVariant { lookup_input });
                if variants.len() == MAX_TOLERANT_VARIANTS {
                    return variants;
                }
            }
        }
    }
    variants
}

pub fn add_tolerant_candidates<F>(
    raw_input: &str,
    parses: &[PinyinParse],
    settings: FuzzyPinyinSettings,
    mut candidates: Vec<Candidate>,
    candidate_page_size: usize,
    mut lookup: F,
) -> Vec<Candidate>
where
    F: FnMut(&str, &[PinyinParse]) -> Vec<Candidate>,
{
    let variants = tolerant_pinyin_variants(raw_input, parses, settings);
    if variants.is_empty() {
        return candidates;
    }

    let parser = PinyinParser;
    let mut seen_texts = candidates
        .iter()
        .map(|candidate| candidate.text.clone())
        .collect::<HashSet<_>>();
    let mut added = 0;
    for variant in variants {
        let variant_parses = parser.parse(variant.lookup_input());
        let normalized_variant =
            PinyinParser::normalize_raw(variant.lookup_input()).replace('\'', "");
        let Some(mut candidate) = lookup(variant.lookup_input(), &variant_parses)
            .into_iter()
            .find(|candidate| compact_pinyin(&candidate.pinyin) == normalized_variant)
        else {
            continue;
        };
        if !seen_texts.insert(candidate.text.clone()) {
            continue;
        }

        candidate.correction = Some(CandidateCorrection {
            kind: CandidateCorrectionKind::FuzzyPinyin,
            confidence: CandidateCorrectionConfidence::Probable,
            edit_distance: 1,
        });
        candidates.push(candidate);
        added += 1;
        if added == MAX_TOLERANT_CANDIDATES {
            break;
        }
    }

    if added == 0 {
        return candidates;
    }
    let visible_limit = if candidate_page_size <= 5 { 1 } else { 2 };
    promote_correction_candidates(candidates, candidate_page_size, visible_limit)
}

fn syllable_alternatives(syllable: &str, settings: FuzzyPinyinSettings) -> Vec<String> {
    let mut alternatives = Vec::new();
    if settings.zh_z {
        push_initial_alternative(&mut alternatives, syllable, "zh", "z");
    }
    if settings.ch_c {
        push_initial_alternative(&mut alternatives, syllable, "ch", "c");
    }
    if settings.sh_s {
        push_initial_alternative(&mut alternatives, syllable, "sh", "s");
    }
    if settings.n_l {
        push_initial_alternative(&mut alternatives, syllable, "n", "l");
    }
    if settings.an_ang {
        push_final_alternative(&mut alternatives, syllable, "ang", "an");
    }
    if settings.en_eng {
        push_final_alternative(&mut alternatives, syllable, "eng", "en");
    }
    if settings.in_ing {
        push_final_alternative(&mut alternatives, syllable, "ing", "in");
    }
    alternatives
}

fn push_initial_alternative(
    alternatives: &mut Vec<String>,
    syllable: &str,
    long: &str,
    short: &str,
) {
    let alternative = if let Some(rest) = syllable.strip_prefix(long) {
        format!("{short}{rest}")
    } else if let Some(rest) = syllable.strip_prefix(short) {
        format!("{long}{rest}")
    } else {
        return;
    };
    push_legal_unique(alternatives, alternative);
}

fn push_final_alternative(alternatives: &mut Vec<String>, syllable: &str, long: &str, short: &str) {
    let alternative = if let Some(stem) = syllable.strip_suffix(long) {
        format!("{stem}{short}")
    } else if let Some(stem) = syllable.strip_suffix(short) {
        format!("{stem}{long}")
    } else {
        return;
    };
    push_legal_unique(alternatives, alternative);
}

fn push_legal_unique(alternatives: &mut Vec<String>, alternative: String) {
    if is_legal_syllable(&alternative) && !alternatives.contains(&alternative) {
        alternatives.push(alternative);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(raw_input: &str) -> Vec<PinyinParse> {
        PinyinParser.parse(raw_input)
    }

    #[test]
    fn disabled_settings_generate_no_variants() {
        assert!(tolerant_pinyin_variants(
            "zongguo",
            &parse("zongguo"),
            FuzzyPinyinSettings::default()
        )
        .is_empty());
    }

    #[test]
    fn enabled_pairs_generate_bidirectional_syllable_variants() {
        let zh_z = FuzzyPinyinSettings {
            zh_z: true,
            ..FuzzyPinyinSettings::default()
        };
        let short_to_long = tolerant_pinyin_variants("zongguo", &parse("zongguo"), zh_z);
        assert!(short_to_long
            .iter()
            .any(|variant| variant.lookup_input() == "zhong'guo"));

        let long_to_short = tolerant_pinyin_variants("zhongguo", &parse("zhongguo"), zh_z);
        assert!(long_to_short
            .iter()
            .any(|variant| variant.lookup_input() == "zong'guo"));

        let in_ing = FuzzyPinyinSettings {
            in_ing: true,
            ..FuzzyPinyinSettings::default()
        };
        assert!(tolerant_pinyin_variants("xin", &parse("xin"), in_ing)
            .iter()
            .any(|variant| variant.lookup_input() == "xing"));
        assert!(tolerant_pinyin_variants("xing", &parse("xing"), in_ing)
            .iter()
            .any(|variant| variant.lookup_input() == "xin"));
    }

    #[test]
    fn one_pair_does_not_activate_unrelated_pairs_or_combinations() {
        let settings = FuzzyPinyinSettings {
            zh_z: true,
            ..FuzzyPinyinSettings::default()
        };
        let variants = tolerant_pinyin_variants("zhan", &parse("zhan"), settings);
        assert_eq!(
            variants
                .iter()
                .map(TolerantPinyinVariant::lookup_input)
                .collect::<Vec<_>>(),
            vec!["zan"]
        );
        assert!(!variants
            .iter()
            .any(|variant| variant.lookup_input() == "zang"));
    }

    #[test]
    fn generation_is_bounded_and_debug_output_is_redacted() {
        let input = "sansansansansansansansan";
        let variants =
            tolerant_pinyin_variants(input, &parse(input), FuzzyPinyinSettings::all_enabled());
        assert_eq!(
            variants.len(),
            MAX_TOLERANT_VARIANTS,
            "the performance fixture must exercise the full variant allowance"
        );
        let debug = format!("{variants:?}");
        assert!(!debug.contains("san"));
        assert!(debug.contains("<redacted>"));
    }

    #[test]
    fn non_ascii_and_overlong_inputs_are_not_expanded() {
        let settings = FuzzyPinyinSettings::all_enabled();
        assert!(tolerant_pinyin_variants("中文", &parse("中文"), settings).is_empty());
        let overlong = "z".repeat(MAX_TOLERANT_INPUT_CHARS + 1);
        assert!(tolerant_pinyin_variants(&overlong, &parse(&overlong), settings).is_empty());
    }
}
