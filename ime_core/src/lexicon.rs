use std::collections::HashSet;

use crate::candidate::{Candidate, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::pinyin_parser::{compact_pinyin, compact_prefix_upper_bound, PinyinParse, PinyinParser};
use crate::ranker::{CandidateMatchKind, Ranker};

const EMBEDDED_BASE_LEXICON: &str = include_str!("../assets/base_lexicon.tsv");
pub const MAX_LOOKUP_CANDIDATES: usize = 50;
const MAX_SEGMENT_CANDIDATES: usize = 8;
const MAX_SEGMENT_SYLLABLES: usize = 4;
const MAX_SEGMENT_OPTIONS_PER_SLICE: usize = 3;

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
    initial_index: Vec<InitialLexiconIndexEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CompactLexiconIndexEntry {
    compact_pinyin: String,
    entry_index: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct InitialLexiconIndexEntry {
    initials: String,
    entry_index: usize,
}

#[derive(Debug, Clone)]
struct SegmentPath {
    text: String,
    pinyin: String,
    score: f64,
    segment_count: usize,
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
        let initial_index = build_initial_index(&entries);

        Ok(Self {
            entries,
            compact_index,
            initial_index,
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
        let mut segmented_candidates = Vec::new();
        let mut initial_exact_candidates = Vec::new();
        let mut prefix_candidates = Vec::new();
        let mut initial_prefix_candidates = Vec::new();
        let mut seen = HashSet::<String>::new();

        let range = self.compact_prefix_range(&normalized_input);
        for indexed_entry in &self.compact_index[range] {
            let entry = &self.entries[indexed_entry.entry_index];
            let exact_match = exact_pinyins.contains(&entry.pinyin);
            let prefix_match = indexed_entry.compact_pinyin.starts_with(&normalized_input);

            if !(exact_match || prefix_match) || !seen.insert(entry.phrase.clone()) {
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

        segmented_candidates.extend(self.segmented_candidates(parses, &mut seen));
        initial_exact_candidates.extend(self.initial_candidates(
            &normalized_input,
            &mut seen,
            true,
        ));
        initial_prefix_candidates.extend(self.initial_candidates(
            &normalized_input,
            &mut seen,
            false,
        ));

        Ranker::sort_candidates(&mut exact_candidates);
        Ranker::sort_candidates(&mut segmented_candidates);
        Ranker::sort_candidates(&mut initial_exact_candidates);
        Ranker::sort_candidates(&mut prefix_candidates);
        Ranker::sort_candidates(&mut initial_prefix_candidates);
        candidates.extend(exact_candidates);
        candidates.extend(segmented_candidates);
        candidates.extend(initial_exact_candidates);
        candidates.extend(prefix_candidates);
        candidates.extend(initial_prefix_candidates);
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

    fn initial_prefix_range(&self, prefix: &str) -> std::ops::Range<usize> {
        let upper_bound = compact_prefix_upper_bound(prefix);
        let start = self
            .initial_index
            .partition_point(|entry| entry.initials.as_str() < prefix);
        let end = self
            .initial_index
            .partition_point(|entry| entry.initials.as_str() < upper_bound.as_str());
        start..end
    }

    fn initial_candidates(
        &self,
        normalized_input: &str,
        seen: &mut HashSet<String>,
        exact_only: bool,
    ) -> Vec<Candidate> {
        if normalized_input.chars().count() < 2 || normalized_input.contains('\'') {
            return Vec::new();
        }

        let mut candidates = Vec::new();
        let range = self.initial_prefix_range(normalized_input);
        for indexed_entry in &self.initial_index[range] {
            let entry = &self.entries[indexed_entry.entry_index];
            let exact_match = indexed_entry.initials == normalized_input;
            if exact_only != exact_match || !seen.insert(entry.phrase.clone()) {
                continue;
            }

            let match_kind = if exact_match {
                CandidateMatchKind::InitialExact
            } else {
                CandidateMatchKind::InitialPrefix
            };
            candidates.push(
                Candidate::new(&entry.phrase, &entry.pinyin, CandidateSource::Base)
                    .with_score(Ranker::score(entry.frequency))
                    .with_rank_score(Ranker::score_match(
                        entry.frequency,
                        match_kind,
                        CandidateSource::Base,
                    )),
            );
        }

        candidates
    }

    fn segmented_candidates(
        &self,
        parses: &[PinyinParse],
        seen: &mut HashSet<String>,
    ) -> Vec<Candidate> {
        let mut candidates = Vec::new();

        for parse in parses.iter().filter(|parse| parse.is_complete()) {
            let syllables = parse.syllable_texts();
            if syllables.len() < 2 {
                continue;
            }

            for path in self.segment_parse(&syllables) {
                if !seen.insert(path.text.clone()) {
                    continue;
                }
                candidates.push(
                    Candidate::new(path.text, path.pinyin, CandidateSource::Base)
                        .with_score(path.score)
                        .with_rank_score(Ranker::score_match(
                            path.score.min(u32::MAX as f64) as u32,
                            CandidateMatchKind::Segmented,
                            CandidateSource::Base,
                        )),
                );
            }
        }

        candidates.truncate(MAX_LOOKUP_CANDIDATES);
        candidates
    }

    fn segment_parse(&self, syllables: &[String]) -> Vec<SegmentPath> {
        let mut dp = vec![Vec::<SegmentPath>::new(); syllables.len() + 1];
        dp[0].push(SegmentPath {
            text: String::new(),
            pinyin: String::new(),
            score: 0.0,
            segment_count: 0,
        });

        for start in 0..syllables.len() {
            if dp[start].is_empty() {
                continue;
            }

            let end_limit = syllables.len().min(start + MAX_SEGMENT_SYLLABLES);
            for end in (start + 1)..=end_limit {
                let pinyin = syllables[start..end].join(" ");
                let segment_candidates =
                    self.exact_candidates_for_pinyin(&pinyin, MAX_SEGMENT_OPTIONS_PER_SLICE);
                if segment_candidates.is_empty() {
                    continue;
                }

                let previous_paths = dp[start].clone();
                for previous in previous_paths {
                    for candidate in &segment_candidates {
                        let mut text = previous.text.clone();
                        text.push_str(&candidate.text);
                        let combined_pinyin = if previous.pinyin.is_empty() {
                            candidate.pinyin.clone()
                        } else {
                            format!("{} {}", previous.pinyin, candidate.pinyin)
                        };
                        dp[end].push(SegmentPath {
                            text,
                            pinyin: combined_pinyin,
                            score: previous.score + candidate.score,
                            segment_count: previous.segment_count + 1,
                        });
                    }
                }

                sort_segment_paths(&mut dp[end]);
            }
        }

        sort_segment_paths(&mut dp[syllables.len()]);
        dp[syllables.len()].clone()
    }

    fn exact_candidates_for_pinyin(&self, pinyin: &str, limit: usize) -> Vec<Candidate> {
        let compact = compact_pinyin(pinyin);
        let range = self.compact_prefix_range(&compact);
        let mut candidates = Vec::new();
        let mut seen = HashSet::<&str>::new();

        for indexed_entry in &self.compact_index[range] {
            if indexed_entry.compact_pinyin != compact {
                continue;
            }

            let entry = &self.entries[indexed_entry.entry_index];
            if entry.pinyin != pinyin || !seen.insert(entry.phrase.as_str()) {
                continue;
            }

            candidates.push(
                Candidate::new(&entry.phrase, &entry.pinyin, CandidateSource::Base)
                    .with_score(Ranker::score(entry.frequency))
                    .with_rank_score(Ranker::score_match(
                        entry.frequency,
                        CandidateMatchKind::Exact,
                        CandidateSource::Base,
                    )),
            );
        }

        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(limit);
        candidates
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

fn build_initial_index(entries: &[LexiconEntry]) -> Vec<InitialLexiconIndexEntry> {
    let mut index = entries
        .iter()
        .enumerate()
        .filter_map(|(entry_index, entry)| {
            let initials = pinyin_initials(&entry.pinyin);
            (!initials.is_empty()).then_some(InitialLexiconIndexEntry {
                initials,
                entry_index,
            })
        })
        .collect::<Vec<_>>();
    index.sort_by(|left, right| {
        left.initials
            .cmp(&right.initials)
            .then_with(|| left.entry_index.cmp(&right.entry_index))
    });
    index
}

fn pinyin_initials(pinyin: &str) -> String {
    pinyin
        .split_whitespace()
        .filter_map(|syllable| syllable.chars().next())
        .collect()
}

fn sort_segment_paths(paths: &mut Vec<SegmentPath>) {
    paths.sort_by(|left, right| {
        right
            .score
            .total_cmp(&left.score)
            .then_with(|| left.segment_count.cmp(&right.segment_count))
            .then_with(|| left.text.cmp(&right.text))
            .then_with(|| left.pinyin.cmp(&right.pinyin))
    });
    paths.dedup_by(|left, right| left.text == right.text);
    paths.truncate(MAX_SEGMENT_CANDIDATES);
}
