use std::collections::{HashMap, HashSet};

use crate::candidate::{Candidate, CandidateSegment, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::pinyin_parser::{compact_pinyin, compact_prefix_upper_bound, PinyinParse, PinyinParser};
use crate::ranker::{CandidateMatchKind, Ranker};

const EMBEDDED_BASE_LEXICON: &str = include_str!("../assets/base_lexicon.tsv");
pub const MAX_LOOKUP_CANDIDATES: usize = 50;
const CONTINUOUS_BEAM_WIDTH: usize = 32;
const MAX_CONTINUOUS_CANDIDATES: usize = 12;
const MAX_CONTINUOUS_OPTIONS_PER_EDGE: usize = 6;

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
    max_compact_pinyin_chars: usize,
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
struct ContinuousPath {
    text: String,
    pinyin: String,
    score: f64,
    segments: Vec<CandidateSegment>,
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
        let max_compact_pinyin_chars = compact_index
            .iter()
            .map(|entry| entry.compact_pinyin.chars().count())
            .max()
            .unwrap_or_default();

        Ok(Self {
            entries,
            compact_index,
            initial_index,
            max_compact_pinyin_chars,
        })
    }

    pub fn entries(&self) -> &[LexiconEntry] {
        &self.entries
    }

    pub fn lookup(&self, raw_input: &str, parses: &[PinyinParse]) -> Vec<Candidate> {
        self.lookup_with_context(raw_input, parses, None, |_, _| 0.0)
    }

    pub fn lookup_with_context(
        &self,
        raw_input: &str,
        parses: &[PinyinParse],
        previous_context: Option<&str>,
        transition_score: impl Fn(&str, &str) -> f64,
    ) -> Vec<Candidate> {
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
        let mut continuous_candidates = Vec::new();
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

        continuous_candidates.extend(self.continuous_candidates(
            raw_input,
            previous_context,
            &transition_score,
            &mut seen,
        ));
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
        Ranker::sort_candidates(&mut continuous_candidates);
        Ranker::sort_candidates(&mut initial_exact_candidates);
        Ranker::sort_candidates(&mut prefix_candidates);
        Ranker::sort_candidates(&mut initial_prefix_candidates);
        candidates.extend(exact_candidates);
        candidates.extend(continuous_candidates);
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

    fn continuous_candidates(
        &self,
        raw_input: &str,
        previous_context: Option<&str>,
        transition_score: &impl Fn(&str, &str) -> f64,
        seen: &mut HashSet<String>,
    ) -> Vec<Candidate> {
        let Some((compact, forced_boundaries)) = compact_input_with_boundaries(raw_input) else {
            return Vec::new();
        };
        let chars = compact.chars().collect::<Vec<_>>();
        if chars.len() < 2 {
            return Vec::new();
        }

        let mut lattice = vec![Vec::<ContinuousPath>::new(); chars.len() + 1];
        lattice[0].push(ContinuousPath {
            text: String::new(),
            pinyin: String::new(),
            score: 0.0,
            segments: Vec::new(),
        });

        for start in 0..chars.len() {
            if lattice[start].is_empty() {
                continue;
            }

            let end_limit = chars
                .len()
                .min(start.saturating_add(self.max_compact_pinyin_chars));
            for end in (start + 1)..=end_limit {
                let compact_edge = chars[start..end].iter().collect::<String>();
                let entries = self.exact_entries_for_compact(
                    &compact_edge,
                    start,
                    end,
                    &forced_boundaries,
                    MAX_CONTINUOUS_OPTIONS_PER_EDGE,
                );
                if entries.is_empty() {
                    continue;
                }

                let previous_paths = lattice[start].clone();
                for previous in previous_paths {
                    for entry in &entries {
                        let left = previous
                            .segments
                            .last()
                            .map(|segment| segment.text.as_str())
                            .or(previous_context);
                        let transition = left
                            .map(|left| transition_score(left, &entry.phrase))
                            .unwrap_or_default();
                        let mut text = previous.text.clone();
                        text.push_str(&entry.phrase);
                        let pinyin = if previous.pinyin.is_empty() {
                            entry.pinyin.clone()
                        } else {
                            format!("{} {}", previous.pinyin, entry.pinyin)
                        };
                        let mut segments = previous.segments.clone();
                        segments.push(CandidateSegment {
                            text: entry.phrase.clone(),
                            pinyin: entry.pinyin.clone(),
                        });
                        lattice[end].push(ContinuousPath {
                            text,
                            pinyin,
                            score: previous.score
                                + Ranker::score_continuous_token(
                                    entry.frequency,
                                    entry.phrase.chars().count(),
                                )
                                + transition,
                            segments,
                        });
                    }
                }

                sort_continuous_paths(&mut lattice[end], CONTINUOUS_BEAM_WIDTH);
            }
        }

        sort_continuous_paths(&mut lattice[chars.len()], MAX_CONTINUOUS_CANDIDATES);
        let mut candidates = Vec::new();
        for path in &lattice[chars.len()] {
            if path.segments.len() < 2 || !seen.insert(path.text.clone()) {
                continue;
            }
            candidates.push(
                Candidate::new(&path.text, &path.pinyin, CandidateSource::Base)
                    .with_score(path.score)
                    .with_rank_score(Ranker::score_continuous_match(path.score))
                    .with_segments(path.segments.clone()),
            );
        }
        candidates
    }

    fn exact_entries_for_compact(
        &self,
        compact: &str,
        start: usize,
        end: usize,
        forced_boundaries: &HashSet<usize>,
        limit: usize,
    ) -> Vec<&LexiconEntry> {
        let range = self.compact_prefix_range(compact);
        let mut entries = Vec::new();
        let mut seen = HashSet::<&str>::new();

        for indexed_entry in &self.compact_index[range] {
            if indexed_entry.compact_pinyin != compact {
                continue;
            }

            let entry = &self.entries[indexed_entry.entry_index];
            if !edge_respects_forced_boundaries(&entry.pinyin, start, end, forced_boundaries)
                || !seen.insert(entry.phrase.as_str())
            {
                continue;
            }
            entries.push(entry);
        }

        entries.sort_by(|left, right| {
            right
                .frequency
                .cmp(&left.frequency)
                .then_with(|| left.phrase.cmp(&right.phrase))
                .then_with(|| left.pinyin.cmp(&right.pinyin))
        });
        entries.truncate(limit);
        entries
    }
}

pub fn merge_user_and_base_candidates(
    user_candidates: Vec<Candidate>,
    base_candidates: Vec<Candidate>,
) -> Vec<Candidate> {
    let segment_paths = base_candidates
        .iter()
        .filter(|candidate| !candidate.segments.is_empty())
        .map(|candidate| (candidate.text.clone(), candidate.segments.clone()))
        .collect::<HashMap<_, _>>();
    let mut combined = user_candidates
        .into_iter()
        .chain(base_candidates)
        .collect::<Vec<_>>();
    Ranker::sort_candidates(&mut combined);

    let mut merged = Vec::new();
    let mut seen = HashSet::new();

    for mut candidate in combined {
        if candidate.segments.is_empty() {
            if let Some(segments) = segment_paths.get(&candidate.text) {
                candidate.segments = segments.clone();
            }
        }
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

fn compact_input_with_boundaries(raw_input: &str) -> Option<(String, HashSet<usize>)> {
    let normalized = PinyinParser::normalize_raw(raw_input);
    if normalized.is_empty()
        || normalized.starts_with('\'')
        || normalized.ends_with('\'')
        || normalized.contains("''")
    {
        return None;
    }

    let mut compact = String::new();
    let mut compact_chars = 0;
    let mut forced_boundaries = HashSet::new();
    for ch in normalized.chars() {
        if ch == '\'' {
            forced_boundaries.insert(compact_chars);
        } else {
            compact.push(ch);
            compact_chars += 1;
        }
    }
    Some((compact, forced_boundaries))
}

fn edge_respects_forced_boundaries(
    pinyin: &str,
    start: usize,
    end: usize,
    forced_boundaries: &HashSet<usize>,
) -> bool {
    let internal_boundaries = forced_boundaries
        .iter()
        .filter(|position| start < **position && **position < end)
        .map(|position| *position - start)
        .collect::<Vec<_>>();
    if internal_boundaries.is_empty() {
        return true;
    }

    let mut offset = 0;
    let mut syllable_boundaries = HashSet::new();
    let syllables = pinyin.split_whitespace().collect::<Vec<_>>();
    for syllable in syllables.iter().take(syllables.len().saturating_sub(1)) {
        offset += syllable.chars().count();
        syllable_boundaries.insert(offset);
    }
    internal_boundaries
        .iter()
        .all(|position| syllable_boundaries.contains(position))
}

fn sort_continuous_paths(paths: &mut Vec<ContinuousPath>, limit: usize) {
    paths.sort_by(|left, right| {
        right
            .score
            .total_cmp(&left.score)
            .then_with(|| left.segments.len().cmp(&right.segments.len()))
            .then_with(|| left.text.cmp(&right.text))
            .then_with(|| left.pinyin.cmp(&right.pinyin))
    });
    paths.dedup_by(|left, right| {
        left.text == right.text
            && left.segments.last().map(|segment| &segment.text)
                == right.segments.last().map(|segment| &segment.text)
    });
    paths.truncate(limit);
}
