use std::collections::HashSet;
use std::fmt;

use crate::candidate::{
    CandidateCorrection, CandidateCorrectionConfidence, CandidateCorrectionKind,
};
use crate::nine_key::is_valid_nine_key_input;

pub const MAX_NINE_KEY_CORRECTIONS: usize = 2;
pub const MAX_NINE_KEY_TYPO_INPUT_DIGITS: usize = 24;
pub const MAX_NINE_KEY_CORRECTION_ATTEMPTS: usize = 64;
const NINE_KEY_CORRECTION_FAMILY_COUNT: usize = 5;
const MIN_NINE_KEY_ATTEMPTS_PER_FAMILY: usize =
    MAX_NINE_KEY_CORRECTION_ATTEMPTS / NINE_KEY_CORRECTION_FAMILY_COUNT;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct NineKeyCorrectionBudget {
    remaining_attempts: usize,
}

impl Default for NineKeyCorrectionBudget {
    fn default() -> Self {
        Self {
            remaining_attempts: MAX_NINE_KEY_CORRECTION_ATTEMPTS,
        }
    }
}

impl NineKeyCorrectionBudget {
    fn consume(&mut self) -> bool {
        if self.remaining_attempts == 0 {
            return false;
        }
        self.remaining_attempts -= 1;
        true
    }

    pub(crate) const fn exhausted(self) -> bool {
        self.remaining_attempts == 0
    }

    #[cfg(test)]
    const fn attempts_used(self) -> usize {
        MAX_NINE_KEY_CORRECTION_ATTEMPTS - self.remaining_attempts
    }
}

#[derive(Clone, PartialEq, Eq)]
pub(crate) struct NineKeyCorrectionSuggestion {
    corrected_digits: String,
    correction: CandidateCorrection,
    priority: u16,
}

impl NineKeyCorrectionSuggestion {
    pub(crate) fn corrected_digits(&self) -> &str {
        &self.corrected_digits
    }

    pub(crate) const fn correction(&self) -> CandidateCorrection {
        self.correction
    }

    pub(crate) const fn priority(&self) -> u16 {
        self.priority
    }
}

impl fmt::Debug for NineKeyCorrectionSuggestion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("NineKeyCorrectionSuggestion")
            .field("corrected_digits", &"<redacted>")
            .field("correction", &self.correction)
            .field("priority", &self.priority)
            .finish()
    }
}

pub(crate) fn suggest_nine_key_corrections(
    digits: &str,
    budget: &mut NineKeyCorrectionBudget,
    mut is_viable: impl FnMut(&str) -> bool,
) -> Vec<NineKeyCorrectionSuggestion> {
    if !is_valid_nine_key_input(digits)
        || digits.len() > MAX_NINE_KEY_TYPO_INPUT_DIGITS
        || budget.exhausted()
    {
        return Vec::new();
    }

    let mut collector = SuggestionCollector {
        raw_digits: digits,
        suggestions: Vec::new(),
        seen: HashSet::new(),
        budget,
        family_remaining_attempts: 0,
        is_viable: &mut is_viable,
    };

    collector.begin_family(4);
    generate_duplicate_digit_removals(digits, &mut collector);
    collector.begin_family(3);
    generate_adjacent_digit_substitutions(digits, &mut collector);
    collector.begin_family(2);
    generate_adjacent_transpositions(digits, &mut collector);
    collector.begin_family(1);
    generate_extra_digit_removals(digits, &mut collector);
    collector.begin_family(0);
    generate_missing_digit_insertions(digits, &mut collector);

    let mut suggestions = collector.suggestions;
    suggestions.sort_by(|left, right| {
        right
            .priority
            .cmp(&left.priority)
            .then_with(|| {
                right
                    .correction
                    .ai_lite_score()
                    .cmp(&left.correction.ai_lite_score())
            })
            .then_with(|| left.corrected_digits.cmp(&right.corrected_digits))
    });
    suggestions
}

struct SuggestionCollector<'a, F> {
    raw_digits: &'a str,
    suggestions: Vec<NineKeyCorrectionSuggestion>,
    seen: HashSet<String>,
    budget: &'a mut NineKeyCorrectionBudget,
    family_remaining_attempts: usize,
    is_viable: &'a mut F,
}

impl<F> SuggestionCollector<'_, F>
where
    F: FnMut(&str) -> bool,
{
    fn begin_family(&mut self, remaining_families: usize) {
        let reserved_attempts = remaining_families.saturating_mul(MIN_NINE_KEY_ATTEMPTS_PER_FAMILY);
        self.family_remaining_attempts = self
            .budget
            .remaining_attempts
            .saturating_sub(reserved_attempts);
    }

    fn push(
        &mut self,
        corrected_digits: String,
        kind: CandidateCorrectionKind,
        confidence: CandidateCorrectionConfidence,
        edit_distance: u8,
        priority: u16,
    ) {
        if corrected_digits == self.raw_digits
            || self.family_remaining_attempts == 0
            || !self.seen.insert(corrected_digits.clone())
            || !self.budget.consume()
        {
            return;
        }
        self.family_remaining_attempts -= 1;
        if !(self.is_viable)(&corrected_digits) {
            return;
        }
        self.suggestions.push(NineKeyCorrectionSuggestion {
            corrected_digits,
            correction: CandidateCorrection {
                kind,
                confidence,
                edit_distance,
            },
            priority,
        });
    }

    fn family_exhausted(&self) -> bool {
        self.family_remaining_attempts == 0 || self.budget.exhausted()
    }
}

fn generate_duplicate_digit_removals<F>(digits: &str, collector: &mut SuggestionCollector<'_, F>)
where
    F: FnMut(&str) -> bool,
{
    let bytes = digits.as_bytes();
    for index in 1..bytes.len() {
        if bytes[index] != bytes[index - 1] {
            continue;
        }
        let mut corrected = digits.to_owned();
        corrected.remove(index);
        collector.push(
            corrected,
            CandidateCorrectionKind::NineKeyExtraDigit,
            CandidateCorrectionConfidence::Probable,
            1,
            900,
        );
        if collector.family_exhausted() {
            return;
        }
    }
}

fn generate_adjacent_digit_substitutions<F>(
    digits: &str,
    collector: &mut SuggestionCollector<'_, F>,
) where
    F: FnMut(&str) -> bool,
{
    for (index, digit) in digits.bytes().enumerate() {
        for replacement in nine_key_neighbors(digit).bytes() {
            let mut corrected = digits.as_bytes().to_vec();
            corrected[index] = replacement;
            collector.push(
                String::from_utf8(corrected)
                    .expect("nine-key digits remain valid after substitution"),
                CandidateCorrectionKind::NineKeyAdjacentDigit,
                CandidateCorrectionConfidence::Probable,
                1,
                800,
            );
            if collector.family_exhausted() {
                return;
            }
        }
    }
}

fn generate_adjacent_transpositions<F>(digits: &str, collector: &mut SuggestionCollector<'_, F>)
where
    F: FnMut(&str) -> bool,
{
    let bytes = digits.as_bytes();
    for index in 0..bytes.len().saturating_sub(1) {
        if bytes[index] == bytes[index + 1] {
            continue;
        }
        let mut corrected = bytes.to_vec();
        corrected.swap(index, index + 1);
        collector.push(
            String::from_utf8(corrected).expect("nine-key digits remain valid after transposition"),
            CandidateCorrectionKind::NineKeyTransposedDigits,
            CandidateCorrectionConfidence::Weak,
            2,
            700,
        );
        if collector.family_exhausted() {
            return;
        }
    }
}

fn generate_extra_digit_removals<F>(digits: &str, collector: &mut SuggestionCollector<'_, F>)
where
    F: FnMut(&str) -> bool,
{
    if digits.len() <= 1 {
        return;
    }
    for index in 0..digits.len() {
        let mut corrected = digits.to_owned();
        corrected.remove(index);
        collector.push(
            corrected,
            CandidateCorrectionKind::NineKeyExtraDigit,
            CandidateCorrectionConfidence::Weak,
            1,
            600,
        );
        if collector.family_exhausted() {
            return;
        }
    }
}

fn generate_missing_digit_insertions<F>(digits: &str, collector: &mut SuggestionCollector<'_, F>)
where
    F: FnMut(&str) -> bool,
{
    for index in 0..=digits.len() {
        let nearby = missing_digit_options(digits.as_bytes(), index);
        for digit in nearby {
            let mut corrected = String::with_capacity(digits.len() + 1);
            corrected.push_str(&digits[..index]);
            corrected.push(char::from(digit));
            corrected.push_str(&digits[index..]);
            collector.push(
                corrected,
                CandidateCorrectionKind::NineKeyMissingDigit,
                CandidateCorrectionConfidence::Weak,
                1,
                500,
            );
            if collector.family_exhausted() {
                return;
            }
        }
    }
}

fn missing_digit_options(digits: &[u8], index: usize) -> Vec<u8> {
    let (left, right) = (
        index.checked_sub(1).and_then(|left| digits.get(left)),
        digits.get(index),
    );
    let mut options = Vec::with_capacity(10);
    for digit in left.into_iter().chain(right).copied() {
        options.push(digit);
        options.extend(nine_key_neighbors(digit).bytes());
    }
    options.sort_unstable();
    options.dedup();
    options
}

fn nine_key_neighbors(digit: u8) -> &'static str {
    match digit {
        b'2' => "3456",
        b'3' => "256",
        b'4' => "2578",
        b'5' => "2346789",
        b'6' => "23589",
        b'7' => "458",
        b'8' => "45679",
        b'9' => "568",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adjacent_missing_extra_and_transposed_digits_are_bounded() {
        let viable = ["626", "64426", "42458"];
        for typed in ["636", "6426", "644426", "64246"] {
            let mut budget = NineKeyCorrectionBudget::default();
            let suggestions = suggest_nine_key_corrections(typed, &mut budget, |candidate| {
                viable.contains(&candidate)
            });
            assert!(!suggestions.is_empty(), "expected a correction for {typed}");
            assert!(budget.attempts_used() <= MAX_NINE_KEY_CORRECTION_ATTEMPTS);
        }
    }

    #[test]
    fn attempt_budget_is_consumed_before_viability_checks() {
        let mut attempts = 0;
        let mut budget = NineKeyCorrectionBudget::default();
        let suggestions =
            suggest_nine_key_corrections("234567892345678923456789", &mut budget, |_| {
                attempts += 1;
                false
            });

        assert!(suggestions.is_empty());
        assert_eq!(attempts, MAX_NINE_KEY_CORRECTION_ATTEMPTS);
        assert_eq!(budget.attempts_used(), MAX_NINE_KEY_CORRECTION_ATTEMPTS);
    }

    #[test]
    fn long_input_keeps_every_edit_family_reachable() {
        let typed = "234567892345678923456789";
        let adjacent = format!("3{}", &typed[1..]);
        let transposed = format!("{}{}{}", &typed[1..2], &typed[..1], &typed[2..]);
        let extra = typed[1..].to_owned();
        let missing = format!("2{typed}");
        let viable = [
            adjacent.as_str(),
            transposed.as_str(),
            extra.as_str(),
            missing.as_str(),
        ];
        let mut budget = NineKeyCorrectionBudget::default();
        let suggestions = suggest_nine_key_corrections(typed, &mut budget, |candidate| {
            viable.contains(&candidate)
        });
        let kinds = suggestions
            .iter()
            .map(|suggestion| suggestion.correction.kind)
            .collect::<Vec<_>>();

        assert!(kinds.contains(&CandidateCorrectionKind::NineKeyAdjacentDigit));
        assert!(kinds.contains(&CandidateCorrectionKind::NineKeyTransposedDigits));
        assert!(kinds.contains(&CandidateCorrectionKind::NineKeyExtraDigit));
        assert!(kinds.contains(&CandidateCorrectionKind::NineKeyMissingDigit));
        assert_eq!(budget.attempts_used(), MAX_NINE_KEY_CORRECTION_ATTEMPTS);
    }

    #[test]
    fn keypad_diagonal_neighbors_are_bidirectional() {
        assert!(nine_key_neighbors(b'2').contains('6'));
        assert!(nine_key_neighbors(b'6').contains('2'));
    }

    #[test]
    fn unsupported_and_overlong_inputs_do_not_generate_corrections() {
        let overlong = "2".repeat(MAX_NINE_KEY_TYPO_INPUT_DIGITS + 1);
        for digits in ["", "120", overlong.as_str()] {
            let mut budget = NineKeyCorrectionBudget::default();
            assert!(suggest_nine_key_corrections(digits, &mut budget, |_| true).is_empty());
        }
    }

    #[test]
    fn debug_output_redacts_digit_signatures() {
        let mut budget = NineKeyCorrectionBudget::default();
        let suggestion =
            suggest_nine_key_corrections("636", &mut budget, |candidate| candidate == "626")
                .remove(0);
        let debug = format!("{suggestion:?}");
        assert!(debug.contains("<redacted>"));
        assert!(!debug.contains("626"));
        assert!(!debug.contains("636"));
    }
}
