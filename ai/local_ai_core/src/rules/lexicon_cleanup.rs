use std::cmp::Reverse;
use std::collections::HashMap;
use std::fmt;

use crate::{AiError, AiErrorCode, AiPrivacyMode};

pub const MAX_CLEANUP_ENTRIES: usize = 10_000;
pub const MAX_CLEANUP_SUGGESTIONS: usize = 128;

const STALE_LOW_FREQUENCY_AGE_MS: i64 = 180 * 24 * 60 * 60 * 1_000;
const STALE_LOW_FREQUENCY_MAX_COUNT: u32 = 1;

#[derive(Clone, PartialEq, Eq)]
pub struct UserLexiconSnapshotEntry {
    phrase: String,
    pinyin: String,
    frequency: u32,
    updated_at_ms: i64,
    user_english_term: bool,
}

impl UserLexiconSnapshotEntry {
    pub fn new(
        phrase: impl Into<String>,
        pinyin: impl Into<String>,
        frequency: u32,
        updated_at_ms: i64,
    ) -> Self {
        Self {
            phrase: phrase.into(),
            pinyin: pinyin.into(),
            frequency,
            updated_at_ms,
            user_english_term: false,
        }
    }

    pub const fn as_user_english_term(mut self, enabled: bool) -> Self {
        self.user_english_term = enabled;
        self
    }

    pub fn phrase(&self) -> &str {
        &self.phrase
    }

    pub fn pinyin(&self) -> &str {
        &self.pinyin
    }

    pub const fn frequency(&self) -> u32 {
        self.frequency
    }

    pub const fn updated_at_ms(&self) -> i64 {
        self.updated_at_ms
    }

    pub const fn is_user_english_term(&self) -> bool {
        self.user_english_term
    }
}

impl fmt::Debug for UserLexiconSnapshotEntry {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserLexiconSnapshotEntry")
            .field("phrase", &"<redacted>")
            .field("pinyin", &"<redacted>")
            .field("frequency", &self.frequency)
            .field("updated_at_ms", &self.updated_at_ms)
            .field("user_english_term", &self.user_english_term)
            .finish()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LexiconCleanupReasonCode {
    DuplicateNormalizedEntry,
    InvalidEnglishTerm,
    StaleLowFrequency,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LexiconCleanupSuggestion {
    entry_index: usize,
    reason_code: LexiconCleanupReasonCode,
}

impl LexiconCleanupSuggestion {
    pub const fn entry_index(self) -> usize {
        self.entry_index
    }

    pub const fn reason_code(self) -> LexiconCleanupReasonCode {
        self.reason_code
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct LexiconCleanupAnalyzer;

impl LexiconCleanupAnalyzer {
    pub fn suggest(
        &self,
        entries: &[UserLexiconSnapshotEntry],
        reference_time_ms: i64,
        privacy_mode: AiPrivacyMode,
    ) -> Result<Vec<LexiconCleanupSuggestion>, AiError> {
        if privacy_mode == AiPrivacyMode::Strict {
            return Err(AiError::new(AiErrorCode::Disabled));
        }
        if entries.len() > MAX_CLEANUP_ENTRIES {
            return Err(AiError::new(AiErrorCode::InputRejectedByPrivacyGuard));
        }

        let duplicates = duplicate_entries(entries);
        let mut suggestions = entries
            .iter()
            .enumerate()
            .filter_map(|(entry_index, entry)| {
                let reason_code = if duplicates.contains_key(&entry_index) {
                    Some(LexiconCleanupReasonCode::DuplicateNormalizedEntry)
                } else if entry.user_english_term && !is_valid_english_term(&entry.phrase) {
                    Some(LexiconCleanupReasonCode::InvalidEnglishTerm)
                } else if is_stale_low_frequency(entry, reference_time_ms) {
                    Some(LexiconCleanupReasonCode::StaleLowFrequency)
                } else {
                    None
                }?;
                Some(LexiconCleanupSuggestion {
                    entry_index,
                    reason_code,
                })
            })
            .collect::<Vec<_>>();
        suggestions.truncate(MAX_CLEANUP_SUGGESTIONS);
        Ok(suggestions)
    }
}

fn duplicate_entries(entries: &[UserLexiconSnapshotEntry]) -> HashMap<usize, ()> {
    let mut grouped = HashMap::<(String, String), Vec<usize>>::new();
    for (index, entry) in entries.iter().enumerate() {
        grouped
            .entry((
                normalize_phrase(&entry.phrase),
                normalize_pinyin(&entry.pinyin),
            ))
            .or_default()
            .push(index);
    }

    let mut duplicates = HashMap::new();
    for indices in grouped.values_mut().filter(|indices| indices.len() > 1) {
        indices.sort_by_key(|index| {
            let entry = &entries[*index];
            (
                Reverse(entry.frequency),
                Reverse(entry.updated_at_ms),
                *index,
            )
        });
        for index in indices.iter().skip(1) {
            duplicates.insert(*index, ());
        }
    }
    duplicates
}

fn is_stale_low_frequency(entry: &UserLexiconSnapshotEntry, reference_time_ms: i64) -> bool {
    entry.frequency <= STALE_LOW_FREQUENCY_MAX_COUNT
        && reference_time_ms.saturating_sub(entry.updated_at_ms) >= STALE_LOW_FREQUENCY_AGE_MS
}

fn is_valid_english_term(value: &str) -> bool {
    let trimmed = value.trim();
    !trimmed.is_empty()
        && trimmed.len() <= 64
        && trimmed
            .chars()
            .any(|character| character.is_ascii_alphabetic())
        && trimmed.chars().all(|character| {
            character.is_ascii_alphanumeric()
                || matches!(character, ' ' | '-' | '_' | '.' | '+' | '#' | '/')
        })
}

fn normalize_phrase(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_ascii_lowercase()
}

fn normalize_pinyin(value: &str) -> String {
    value
        .bytes()
        .filter(|byte| byte.is_ascii_alphanumeric())
        .map(|byte| byte.to_ascii_lowercase() as char)
        .collect()
}
