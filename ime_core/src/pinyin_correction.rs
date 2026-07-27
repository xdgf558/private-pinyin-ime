use std::collections::HashSet;
use std::fmt;
use std::sync::OnceLock;

use crate::candidate::{
    promote_correction_candidates, Candidate, CandidateCorrection, CandidateCorrectionConfidence,
    CandidateCorrectionKind,
};
use crate::error::{ImeError, ImeResult};
use crate::pinyin_parser::{compact_pinyin, PinyinParse, PinyinParser};

pub const MAX_PINYIN_CORRECTIONS: usize = 2;
pub const MAX_TYPO_INPUT_CHARS: usize = 24;
pub const MAX_CORRECTION_ATTEMPTS: usize = 64;

const CORRECTIONS_TSV: &str = include_str!("../../ai/local_ai_core/assets/pinyin_corrections.tsv");
const CORRECTIONS_HEADER: &str = "typed\tcorrected\treason\tpriority\tprovenance";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RuleReason {
    CommonConfusion,
    DuplicateLetter,
    MissingMedial,
}

impl RuleReason {
    fn parse(value: &str) -> Option<Self> {
        match value {
            "common_confusion" => Some(Self::CommonConfusion),
            "duplicate_letter" => Some(Self::DuplicateLetter),
            "missing_medial" => Some(Self::MissingMedial),
            _ => None,
        }
    }

    const fn candidate_kind(self) -> CandidateCorrectionKind {
        match self {
            Self::CommonConfusion => CandidateCorrectionKind::CommonConfusion,
            Self::DuplicateLetter => CandidateCorrectionKind::DuplicateLetter,
            Self::MissingMedial => CandidateCorrectionKind::MissingMedial,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CorrectionRule {
    typed: String,
    corrected: String,
    reason: RuleReason,
    priority: u16,
}

#[derive(Clone, PartialEq, Eq)]
pub struct PinyinCorrectionSuggestion {
    corrected_pinyin: String,
    correction: CandidateCorrection,
    priority: u16,
}

impl PinyinCorrectionSuggestion {
    pub fn corrected_pinyin(&self) -> &str {
        &self.corrected_pinyin
    }

    pub const fn correction(&self) -> CandidateCorrection {
        self.correction
    }
}

impl fmt::Debug for PinyinCorrectionSuggestion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PinyinCorrectionSuggestion")
            .field("corrected_pinyin", &"<redacted>")
            .field("correction", &self.correction)
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PinyinCorrector {
    rules: Vec<CorrectionRule>,
}

struct SuggestionCollector<'a, F> {
    raw_pinyin: &'a str,
    suggestions: Vec<PinyinCorrectionSuggestion>,
    seen_corrections: HashSet<String>,
    remaining_attempts: usize,
    is_viable: &'a mut F,
}

impl<'a, F> SuggestionCollector<'a, F>
where
    F: FnMut(&str) -> bool,
{
    fn new(raw_pinyin: &'a str, is_viable: &'a mut F) -> Self {
        Self {
            raw_pinyin,
            suggestions: Vec::new(),
            seen_corrections: HashSet::new(),
            remaining_attempts: MAX_CORRECTION_ATTEMPTS,
            is_viable,
        }
    }

    fn push(
        &mut self,
        corrected: String,
        kind: CandidateCorrectionKind,
        confidence: CandidateCorrectionConfidence,
        priority: u16,
    ) {
        if corrected == self.raw_pinyin
            || self.remaining_attempts == 0
            || !self.seen_corrections.insert(corrected.clone())
        {
            return;
        }
        let Some(edit_distance) = bounded_edit_distance(self.raw_pinyin, &corrected, 3) else {
            return;
        };
        self.remaining_attempts -= 1;
        if !(self.is_viable)(&corrected) {
            return;
        }
        self.suggestions.push(PinyinCorrectionSuggestion {
            corrected_pinyin: corrected,
            correction: CandidateCorrection {
                kind,
                confidence,
                edit_distance,
            },
            priority,
        });
    }

    const fn exhausted(&self) -> bool {
        self.remaining_attempts == 0
    }

    fn finish(self) -> Vec<PinyinCorrectionSuggestion> {
        self.suggestions
    }
}

impl PinyinCorrector {
    fn embedded() -> Self {
        Self::from_tsv(CORRECTIONS_TSV).expect("embedded pinyin correction rules must remain valid")
    }

    fn from_tsv(contents: &str) -> ImeResult<Self> {
        let mut lines = contents.lines().filter(|line| !line.trim().is_empty());
        if lines.next() != Some(CORRECTIONS_HEADER) {
            return Err(ImeError::InvalidPinyinCorrectionRules);
        }

        let mut rules = Vec::new();
        let mut seen = HashSet::new();
        for line in lines {
            let fields = line.split('\t').collect::<Vec<_>>();
            if fields.len() != 5
                || !is_compact_ascii_pinyin(fields[0])
                || !is_compact_ascii_pinyin(fields[1])
                || fields[4] != "first_party"
            {
                return Err(ImeError::InvalidPinyinCorrectionRules);
            }
            let reason =
                RuleReason::parse(fields[2]).ok_or(ImeError::InvalidPinyinCorrectionRules)?;
            let priority = fields[3]
                .parse::<u16>()
                .map_err(|_| ImeError::InvalidPinyinCorrectionRules)?;
            if !seen.insert((fields[0], fields[1])) {
                return Err(ImeError::InvalidPinyinCorrectionRules);
            }
            rules.push(CorrectionRule {
                typed: fields[0].to_owned(),
                corrected: fields[1].to_owned(),
                reason,
                priority,
            });
        }
        if rules.is_empty() {
            return Err(ImeError::InvalidPinyinCorrectionRules);
        }
        Ok(Self { rules })
    }

    pub fn suggest<F>(
        &self,
        raw_pinyin: &str,
        allow_generic_corrections: bool,
        mut is_viable: F,
    ) -> Vec<PinyinCorrectionSuggestion>
    where
        F: FnMut(&str) -> bool,
    {
        if !is_compact_ascii_pinyin(raw_pinyin)
            || raw_pinyin.len() < 3
            || raw_pinyin.len() > MAX_TYPO_INPUT_CHARS
        {
            return Vec::new();
        }

        let mut collector = SuggestionCollector::new(raw_pinyin, &mut is_viable);
        for rule in &self.rules {
            for (start, _) in raw_pinyin.match_indices(&rule.typed) {
                let end = start + rule.typed.len();
                let mut corrected = String::with_capacity(
                    raw_pinyin.len() + rule.corrected.len().saturating_sub(rule.typed.len()),
                );
                corrected.push_str(&raw_pinyin[..start]);
                corrected.push_str(&rule.corrected);
                corrected.push_str(&raw_pinyin[end..]);
                collector.push(
                    corrected,
                    rule.reason.candidate_kind(),
                    CandidateCorrectionConfidence::Exact,
                    rule.priority.saturating_add(1_000),
                );
                if collector.exhausted() {
                    break;
                }
            }
            if collector.exhausted() {
                break;
            }
        }

        if allow_generic_corrections && !collector.exhausted() {
            generate_duplicate_letter_corrections(raw_pinyin, &mut collector);
            generate_adjacent_transpositions(raw_pinyin, &mut collector);
            generate_adjacent_key_corrections(raw_pinyin, &mut collector);
        }

        let mut suggestions = collector.finish();
        suggestions.sort_by(|left, right| {
            right
                .priority
                .cmp(&left.priority)
                .then_with(|| {
                    left.correction
                        .edit_distance
                        .cmp(&right.correction.edit_distance)
                })
                .then_with(|| left.corrected_pinyin.cmp(&right.corrected_pinyin))
        });
        suggestions.truncate(MAX_PINYIN_CORRECTIONS);
        suggestions
    }
}

pub fn embedded_pinyin_corrector() -> &'static PinyinCorrector {
    static CORRECTOR: OnceLock<PinyinCorrector> = OnceLock::new();
    CORRECTOR.get_or_init(PinyinCorrector::embedded)
}

pub fn add_correction_candidates<F>(
    raw_input: &str,
    parses: &[PinyinParse],
    mut candidates: Vec<Candidate>,
    candidate_page_size: usize,
    mut lookup: F,
) -> Vec<Candidate>
where
    F: FnMut(&str, &[PinyinParse]) -> Vec<Candidate>,
{
    let normalized = PinyinParser::normalize_raw(raw_input);
    // TYPO-01 is intentionally limited to compact ASCII full-keyboard pinyin.
    if normalized.contains('\'') || !raw_input.is_ascii() {
        return candidates;
    }

    let has_complete_parse = parses.iter().any(PinyinParse::is_complete);
    let parser = PinyinParser;
    let suggestions =
        embedded_pinyin_corrector().suggest(&normalized, !has_complete_parse, |corrected| {
            parser.parse(corrected).iter().any(PinyinParse::is_complete)
        });
    if suggestions.is_empty() {
        return candidates;
    }

    for suggestion in suggestions {
        let corrected_parses = parser.parse(suggestion.corrected_pinyin());
        let normalized_correction = PinyinParser::normalize_raw(suggestion.corrected_pinyin());
        let Some(mut candidate) = lookup(suggestion.corrected_pinyin(), &corrected_parses)
            .into_iter()
            .find(|candidate| compact_pinyin(&candidate.pinyin) == normalized_correction)
        else {
            continue;
        };
        candidate.correction = Some(suggestion.correction());

        if let Some(existing_index) = candidates
            .iter()
            .position(|existing| existing.text == candidate.text)
        {
            candidates[existing_index].correction = candidate.correction;
        } else {
            candidates.push(candidate);
        }
    }

    let correction_count = candidates
        .iter()
        .filter(|candidate| candidate.correction.is_some())
        .count();
    if correction_count == 0 {
        return candidates;
    }
    debug_assert!(correction_count <= MAX_PINYIN_CORRECTIONS);

    let visible_correction_limit = if candidate_page_size <= 5 { 1 } else { 2 };
    promote_correction_candidates(candidates, candidate_page_size, visible_correction_limit)
}

fn generate_duplicate_letter_corrections<F>(
    raw_pinyin: &str,
    collector: &mut SuggestionCollector<'_, F>,
) where
    F: FnMut(&str) -> bool,
{
    let bytes = raw_pinyin.as_bytes();
    for index in 1..bytes.len() {
        if bytes[index] != bytes[index - 1] {
            continue;
        }
        let mut corrected = raw_pinyin.to_owned();
        corrected.remove(index);
        collector.push(
            corrected,
            CandidateCorrectionKind::DuplicateLetter,
            CandidateCorrectionConfidence::Probable,
            800,
        );
        if collector.exhausted() {
            return;
        }
    }
}

fn generate_adjacent_transpositions<F>(raw_pinyin: &str, collector: &mut SuggestionCollector<'_, F>)
where
    F: FnMut(&str) -> bool,
{
    let bytes = raw_pinyin.as_bytes();
    for index in 0..bytes.len().saturating_sub(1) {
        if bytes[index] == bytes[index + 1] {
            continue;
        }
        let mut corrected = bytes.to_vec();
        corrected.swap(index, index + 1);
        let corrected =
            String::from_utf8(corrected).expect("ASCII pinyin remains valid after a swap");
        collector.push(
            corrected,
            CandidateCorrectionKind::TransposedLetters,
            CandidateCorrectionConfidence::Weak,
            750,
        );
        if collector.exhausted() {
            return;
        }
    }
}

fn generate_adjacent_key_corrections<F>(
    raw_pinyin: &str,
    collector: &mut SuggestionCollector<'_, F>,
) where
    F: FnMut(&str) -> bool,
{
    for (index, byte) in raw_pinyin.bytes().enumerate() {
        for replacement in qwerty_neighbors(byte).bytes() {
            let mut corrected = raw_pinyin.as_bytes().to_vec();
            corrected[index] = replacement;
            let corrected = String::from_utf8(corrected)
                .expect("ASCII pinyin remains valid after an adjacent-key replacement");
            collector.push(
                corrected,
                CandidateCorrectionKind::AdjacentKey,
                CandidateCorrectionConfidence::Probable,
                700,
            );
            if collector.exhausted() {
                return;
            }
        }
    }
}

fn bounded_edit_distance(left: &str, right: &str, limit: u8) -> Option<u8> {
    let left = left.as_bytes();
    let right = right.as_bytes();
    if left.len().abs_diff(right.len()) > usize::from(limit) {
        return None;
    }

    let mut previous = (0..=right.len()).collect::<Vec<_>>();
    let mut current = vec![0; right.len() + 1];
    for (left_index, left_byte) in left.iter().enumerate() {
        current[0] = left_index + 1;
        let mut row_minimum = current[0];
        for (right_index, right_byte) in right.iter().enumerate() {
            let substitution = previous[right_index] + usize::from(left_byte != right_byte);
            current[right_index + 1] = substitution
                .min(previous[right_index + 1] + 1)
                .min(current[right_index] + 1);
            row_minimum = row_minimum.min(current[right_index + 1]);
        }
        if row_minimum > usize::from(limit) {
            return None;
        }
        std::mem::swap(&mut previous, &mut current);
    }

    let distance = previous[right.len()];
    (distance <= usize::from(limit)).then_some(distance as u8)
}

fn is_compact_ascii_pinyin(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_lowercase())
}

fn qwerty_neighbors(byte: u8) -> &'static str {
    match byte {
        b'q' => "wa",
        b'w' => "qeas",
        b'e' => "wrsd",
        b'r' => "etdf",
        b't' => "rygf",
        b'y' => "tuhg",
        b'u' => "yijh",
        b'i' => "uokj",
        b'o' => "iplk",
        b'p' => "ol",
        b'a' => "qwsz",
        b's' => "wedxza",
        b'd' => "erfcxs",
        b'f' => "rtgvcd",
        b'g' => "tyhbvf",
        b'h' => "yujnbg",
        b'j' => "uikmnh",
        b'k' => "iolmj",
        b'l' => "opk",
        b'z' => "asx",
        b'x' => "zsdc",
        b'c' => "xdfv",
        b'v' => "cfgb",
        b'b' => "vghn",
        b'n' => "bhjm",
        b'm' => "njk",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn complete_pinyin(value: &str) -> bool {
        PinyinParser
            .parse(value)
            .iter()
            .any(PinyinParse::is_complete)
    }

    #[test]
    fn approved_rules_remain_bounded_and_deterministic() {
        let suggestions = embedded_pinyin_corrector().suggest("zongguo", false, complete_pinyin);
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].corrected_pinyin(), "zhongguo");
        assert_eq!(
            suggestions[0].correction().kind,
            CandidateCorrectionKind::CommonConfusion
        );
        assert_eq!(
            suggestions[0].correction().confidence,
            CandidateCorrectionConfidence::Exact
        );
    }

    #[test]
    fn adjacent_key_and_transposition_typos_are_corrected() {
        let adjacent = embedded_pinyin_corrector().suggest("nihap", true, complete_pinyin);
        assert!(adjacent
            .iter()
            .any(|suggestion| suggestion.corrected_pinyin() == "nihao"));

        let transposed = embedded_pinyin_corrector().suggest("nihoa", true, complete_pinyin);
        assert!(transposed
            .iter()
            .any(|suggestion| suggestion.corrected_pinyin() == "nihao"));
    }

    #[test]
    fn generic_corrections_bound_parser_attempts_before_acceptance() {
        let mut attempts = 0;
        let suggestions =
            embedded_pinyin_corrector().suggest("wojintianxiangquchifanzx", true, |_| {
                attempts += 1;
                false
            });

        assert!(suggestions.is_empty());
        assert_eq!(attempts, MAX_CORRECTION_ATTEMPTS);
    }

    #[test]
    fn normal_pinyin_and_unsupported_input_do_not_regress() {
        assert!(embedded_pinyin_corrector()
            .suggest("nihao", false, complete_pinyin)
            .is_empty());
        assert!(embedded_pinyin_corrector()
            .suggest("ni'hao", true, complete_pinyin)
            .is_empty());
        assert!(embedded_pinyin_corrector()
            .suggest(&"a".repeat(MAX_TYPO_INPUT_CHARS + 1), true, complete_pinyin)
            .is_empty());
    }

    #[test]
    fn correction_debug_output_redacts_composition_text() {
        let suggestion = embedded_pinyin_corrector()
            .suggest("nhao", false, complete_pinyin)
            .remove(0);
        let debug = format!("{suggestion:?}");
        assert!(debug.contains("<redacted>"));
        assert!(!debug.contains("nihao"));
        assert!(!debug.contains("nhao"));
    }
}
