use std::collections::HashSet;

use crate::candidate::{Candidate, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::pinyin_parser::{compact_pinyin, compact_prefix_upper_bound, PinyinParse, PinyinParser};
use crate::ranker::{CandidateMatchKind, Ranker};

const EMBEDDED_BASE_LEXICON: &str = include_str!("../assets/base_lexicon_sample.tsv");
pub const MAX_LOOKUP_CANDIDATES: usize = 50;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LexiconEntry {
    pub phrase: String,
    pub pinyin: String,
    pub frequency: u32,
}

#[derive(Debug, Clone, Default)]
pub struct Lexicon {
    entries: Vec<LexiconEntry>,
    compact_index: Vec<CompactLexiconIndexEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CompactLexiconIndexEntry {
    compact_pinyin: String,
    entry_index: usize,
}

impl Lexicon {
    pub fn load_embedded() -> ImeResult<Self> {
        Self::from_tsv(EMBEDDED_BASE_LEXICON)
    }

    pub fn from_tsv(tsv: &str) -> ImeResult<Self> {
        let mut entries = Vec::new();

        for (line_index, line) in tsv.lines().enumerate() {
            if line.trim().is_empty() {
                continue;
            }

            if line_index == 0 && is_header_line(line) {
                continue;
            }

            let mut fields = line.split('\t');
            let phrase = fields
                .next()
                .filter(|value| !value.is_empty())
                .ok_or(ImeError::MissingLexiconField)?;
            let pinyin = fields
                .next()
                .filter(|value| !value.is_empty())
                .ok_or(ImeError::MissingLexiconField)?;
            let frequency = fields
                .next()
                .ok_or(ImeError::MissingLexiconField)?
                .parse::<u32>()
                .map_err(|_| ImeError::InvalidLexiconFrequency)?;

            if fields.next().is_some() {
                return Err(ImeError::InvalidLexiconFormat);
            }

            entries.push(LexiconEntry {
                phrase: phrase.to_owned(),
                pinyin: pinyin.to_owned(),
                frequency,
            });
        }

        let compact_index = build_compact_index(&entries);

        Ok(Self {
            entries,
            compact_index,
        })
    }

    pub fn entries(&self) -> &[LexiconEntry] {
        &self.entries
    }

    pub fn lookup(&self, raw_input: &str, parses: &[PinyinParse]) -> Vec<Candidate> {
        if raw_input.trim().is_empty() {
            return Vec::new();
        }

        let normalized_input = PinyinParser::normalize_raw(raw_input).replace('\'', "");
        let exact_pinyins = parses
            .iter()
            .filter(|parse| parse.is_complete())
            .map(PinyinParse::pinyin_string)
            .collect::<HashSet<_>>();

        let mut candidates = Vec::new();
        let mut exact_candidates = Vec::new();
        let mut prefix_candidates = Vec::new();
        let mut seen = HashSet::<&str>::new();

        let range = self.compact_prefix_range(&normalized_input);
        for indexed_entry in &self.compact_index[range] {
            let entry = &self.entries[indexed_entry.entry_index];
            let exact_match = exact_pinyins.contains(&entry.pinyin);
            let prefix_match = indexed_entry.compact_pinyin.starts_with(&normalized_input);

            if !(exact_match || prefix_match) || !seen.insert(entry.phrase.as_str()) {
                continue;
            }

            let match_kind = if exact_match {
                CandidateMatchKind::Exact
            } else {
                CandidateMatchKind::Prefix
            };
            let candidate = Candidate::new(&entry.phrase, &entry.pinyin, CandidateSource::Base)
                .with_score(Ranker::score(entry.frequency))
                .with_rank_score(Ranker::score_match(
                    entry.frequency,
                    match_kind,
                    CandidateSource::Base,
                ));

            if exact_match {
                exact_candidates.push(candidate);
            } else {
                prefix_candidates.push(candidate);
            }
        }

        Ranker::sort_candidates(&mut exact_candidates);
        Ranker::sort_candidates(&mut prefix_candidates);
        candidates.extend(exact_candidates);
        candidates.extend(prefix_candidates);
        candidates.truncate(MAX_LOOKUP_CANDIDATES);
        candidates
    }

    fn compact_prefix_range(&self, prefix: &str) -> std::ops::Range<usize> {
        let upper_bound = compact_prefix_upper_bound(prefix);
        let start = self
            .compact_index
            .partition_point(|entry| entry.compact_pinyin.as_str() < prefix);
        let end = self
            .compact_index
            .partition_point(|entry| entry.compact_pinyin.as_str() < upper_bound.as_str());
        start..end
    }
}

pub fn merge_user_and_base_candidates(
    user_candidates: Vec<Candidate>,
    base_candidates: Vec<Candidate>,
) -> Vec<Candidate> {
    let mut combined = user_candidates
        .into_iter()
        .chain(base_candidates)
        .collect::<Vec<_>>();
    Ranker::sort_candidates(&mut combined);

    let mut merged = Vec::new();
    let mut seen = HashSet::new();

    for candidate in combined {
        if seen.insert(candidate.text.clone()) {
            merged.push(candidate);
        }
    }

    merged.truncate(MAX_LOOKUP_CANDIDATES);
    merged
}

fn is_header_line(line: &str) -> bool {
    line == "phrase\tpinyin\tfrequency"
}

fn build_compact_index(entries: &[LexiconEntry]) -> Vec<CompactLexiconIndexEntry> {
    let mut index = entries
        .iter()
        .enumerate()
        .map(|(entry_index, entry)| CompactLexiconIndexEntry {
            compact_pinyin: compact_pinyin(&entry.pinyin),
            entry_index,
        })
        .collect::<Vec<_>>();
    index.sort_by(|left, right| {
        left.compact_pinyin
            .cmp(&right.compact_pinyin)
            .then_with(|| left.entry_index.cmp(&right.entry_index))
    });
    index
}
