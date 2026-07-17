use std::collections::HashSet;
use std::fmt;

pub const MAX_PINYIN_CORRECTIONS: usize = 2;

const CORRECTIONS_TSV: &str = include_str!("../../assets/pinyin_corrections.tsv");
const CORRECTIONS_HEADER: &str = "typed\tcorrected\treason\tpriority\tprovenance";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PinyinCorrectionReason {
    CommonConfusion,
    DuplicateLetter,
    MissingMedial,
}

impl PinyinCorrectionReason {
    fn parse(value: &str) -> Option<Self> {
        match value {
            "common_confusion" => Some(Self::CommonConfusion),
            "duplicate_letter" => Some(Self::DuplicateLetter),
            "missing_medial" => Some(Self::MissingMedial),
            _ => None,
        }
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct PinyinCorrectionSuggestion {
    corrected_pinyin: String,
    edit_distance: u8,
    reason: PinyinCorrectionReason,
}

impl PinyinCorrectionSuggestion {
    pub fn corrected_pinyin(&self) -> &str {
        &self.corrected_pinyin
    }

    pub const fn edit_distance(&self) -> u8 {
        self.edit_distance
    }

    pub const fn reason(&self) -> PinyinCorrectionReason {
        self.reason
    }
}

impl fmt::Debug for PinyinCorrectionSuggestion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PinyinCorrectionSuggestion")
            .field("corrected_pinyin", &"<redacted>")
            .field("edit_distance", &self.edit_distance)
            .field("reason", &self.reason)
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CorrectionRule {
    typed: String,
    corrected: String,
    reason: PinyinCorrectionReason,
    priority: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PinyinCorrector {
    rules: Vec<CorrectionRule>,
}

impl PinyinCorrector {
    pub fn embedded() -> Self {
        Self::from_tsv(CORRECTIONS_TSV).unwrap_or_else(|_| Self { rules: Vec::new() })
    }

    pub fn from_tsv(contents: &str) -> Result<Self, RulesDataError> {
        let mut lines = contents.lines().filter(|line| !line.trim().is_empty());
        if lines.next() != Some(CORRECTIONS_HEADER) {
            return Err(RulesDataError::InvalidHeader);
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
                return Err(RulesDataError::InvalidRow);
            }
            let reason =
                PinyinCorrectionReason::parse(fields[2]).ok_or(RulesDataError::InvalidRow)?;
            let priority = fields[3]
                .parse::<u16>()
                .map_err(|_| RulesDataError::InvalidRow)?;
            let key = (fields[0].to_owned(), fields[1].to_owned());
            if !seen.insert(key) {
                return Err(RulesDataError::DuplicateRule);
            }
            rules.push(CorrectionRule {
                typed: fields[0].to_owned(),
                corrected: fields[1].to_owned(),
                reason,
                priority,
            });
        }
        if rules.is_empty() {
            return Err(RulesDataError::EmptyData);
        }
        Ok(Self { rules })
    }

    pub fn suggest(&self, raw_pinyin: &str) -> Vec<PinyinCorrectionSuggestion> {
        self.suggest_with_validator(raw_pinyin, |_| true)
    }

    pub fn suggest_with_validator<F>(
        &self,
        raw_pinyin: &str,
        mut is_viable: F,
    ) -> Vec<PinyinCorrectionSuggestion>
    where
        F: FnMut(&str) -> bool,
    {
        if !is_compact_ascii_pinyin(raw_pinyin) {
            return Vec::new();
        }

        let mut candidates = Vec::<RankedCorrection>::new();
        for rule in &self.rules {
            for (start, _) in raw_pinyin.match_indices(&rule.typed) {
                let end = start + rule.typed.len();
                let mut corrected = String::with_capacity(
                    raw_pinyin.len() + rule.corrected.len().saturating_sub(rule.typed.len()),
                );
                corrected.push_str(&raw_pinyin[..start]);
                corrected.push_str(&rule.corrected);
                corrected.push_str(&raw_pinyin[end..]);
                push_correction(
                    &mut candidates,
                    raw_pinyin,
                    corrected,
                    rule.reason,
                    rule.priority,
                    &mut is_viable,
                );
            }
        }

        candidates.sort_by(|left, right| {
            right
                .priority
                .cmp(&left.priority)
                .then_with(|| {
                    left.suggestion
                        .edit_distance
                        .cmp(&right.suggestion.edit_distance)
                })
                .then_with(|| {
                    left.suggestion
                        .corrected_pinyin
                        .cmp(&right.suggestion.corrected_pinyin)
                })
        });
        candidates.dedup_by(|left, right| {
            left.suggestion.corrected_pinyin == right.suggestion.corrected_pinyin
        });
        candidates
            .into_iter()
            .take(MAX_PINYIN_CORRECTIONS)
            .map(|candidate| candidate.suggestion)
            .collect()
    }
}

impl Default for PinyinCorrector {
    fn default() -> Self {
        Self::embedded()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RulesDataError {
    InvalidHeader,
    InvalidRow,
    DuplicateRule,
    EmptyData,
}

#[derive(Debug)]
struct RankedCorrection {
    suggestion: PinyinCorrectionSuggestion,
    priority: u16,
}

fn push_correction<F>(
    candidates: &mut Vec<RankedCorrection>,
    raw_pinyin: &str,
    corrected: String,
    reason: PinyinCorrectionReason,
    priority: u16,
    is_viable: &mut F,
) where
    F: FnMut(&str) -> bool,
{
    if corrected == raw_pinyin || !is_viable(&corrected) {
        return;
    }
    let Some(edit_distance) = bounded_edit_distance(raw_pinyin, &corrected, 3) else {
        return;
    };
    candidates.push(RankedCorrection {
        suggestion: PinyinCorrectionSuggestion {
            corrected_pinyin: corrected,
            edit_distance,
            reason,
        },
        priority,
    });
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
