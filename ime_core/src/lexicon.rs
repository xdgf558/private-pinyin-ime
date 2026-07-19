use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::path::Path;

use crate::candidate::{Candidate, CandidateSegment, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::imported_lexicon::{
    read_utf8_file_bounded, validate_imported_entries, MAX_IMPORTED_FILE_BYTES,
};
use crate::nine_key::{is_valid_nine_key_input, pinyin_to_nine_key};
use crate::pinyin_parser::{compact_pinyin, compact_prefix_upper_bound, PinyinParse, PinyinParser};
use crate::ranker::{CandidateMatchKind, Ranker};
use crate::syllable::is_legal_syllable;

const EMBEDDED_BASE_LEXICON: &str = include_str!("../assets/base_lexicon.tsv");
pub const MAX_LOOKUP_CANDIDATES: usize = 50;
const CONTINUOUS_BEAM_WIDTH: usize = 32;
const MAX_CONTINUOUS_CANDIDATES: usize = 12;
const MAX_CONTINUOUS_OPTIONS_PER_EDGE: usize = 6;
const MAX_MIXED_INPUT_PARSES: usize = 16;
const MAX_MIXED_INPUT_CHARS: usize = 16;
const MAX_PINYIN_SYLLABLE_CHARS: usize = 6;

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
    nine_key_index: Vec<NineKeyLexiconIndexEntry>,
    max_compact_pinyin_chars: usize,
    max_initial_chars: usize,
    max_nine_key_chars: usize,
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

#[derive(Debug, Clone, PartialEq, Eq)]
struct NineKeyLexiconIndexEntry {
    digits: String,
    entry_index: usize,
}

#[derive(Debug, Clone)]
struct ContinuousPath {
    text: String,
    pinyin: String,
    score: f64,
    segments: Vec<CandidateSegment>,
    abbreviated_syllables: usize,
    full_pinyin_chars: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ContinuousEdgeKind {
    FullPinyin,
    Initials { syllables: usize },
}

#[derive(Debug, Clone, Copy)]
struct ContinuousEdge<'a> {
    entry: &'a LexiconEntry,
    kind: ContinuousEdgeKind,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MixedInputToken {
    text: String,
    abbreviated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MixedInputParse {
    tokens: Vec<MixedInputToken>,
    abbreviated_syllables: usize,
    full_pinyin_chars: usize,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct ContinuousDecodeCache {
    compact_input: String,
    forced_boundaries: HashSet<usize>,
    previous_context: Option<String>,
    lattice: Vec<Vec<ContinuousPath>>,
    #[cfg(test)]
    last_reused_chars: usize,
}

impl ContinuousDecodeCache {
    pub(crate) fn clear(&mut self) {
        *self = Self::default();
    }

    fn prepare(
        &mut self,
        compact_input: &str,
        forced_boundaries: &HashSet<usize>,
        previous_context: Option<&str>,
    ) -> usize {
        let input_chars = compact_input.chars().count();
        let mut reusable_chars = if self.previous_context.as_deref() == previous_context {
            common_prefix_chars(&self.compact_input, compact_input)
                .min(self.lattice.len().saturating_sub(1))
                .min(input_chars)
        } else {
            0
        };

        for position in 1..reusable_chars {
            if self.forced_boundaries.contains(&position) != forced_boundaries.contains(&position) {
                reusable_chars = position;
                break;
            }
        }

        if reusable_chars == 0 || self.lattice.is_empty() {
            self.lattice = vec![Vec::new(); input_chars + 1];
            self.lattice[0].push(ContinuousPath {
                text: String::new(),
                pinyin: String::new(),
                score: 0.0,
                segments: Vec::new(),
                abbreviated_syllables: 0,
                full_pinyin_chars: 0,
            });
        } else {
            self.lattice.truncate(reusable_chars + 1);
            self.lattice.resize_with(input_chars + 1, Vec::new);
        }

        self.compact_input.clear();
        self.compact_input.push_str(compact_input);
        self.forced_boundaries.clone_from(forced_boundaries);
        self.previous_context = previous_context.map(str::to_owned);
        #[cfg(test)]
        {
            self.last_reused_chars = reusable_chars;
        }
        reusable_chars
    }
}

impl Lexicon {
    pub fn load_embedded() -> ImeResult<Self> {
        Self::from_tsv(EMBEDDED_BASE_LEXICON)
    }

    pub fn load_embedded_with_imported(path: impl AsRef<Path>) -> ImeResult<Self> {
        let path = path.as_ref();
        let mut entries = Self::load_embedded()?.entries;
        let imported = read_utf8_file_bounded(path, MAX_IMPORTED_FILE_BYTES)?;
        let imported_entries = Self::from_tsv(&imported)
            .map_err(|_| ImeError::ImportedLexiconParse)?
            .entries;
        validate_imported_entries(&imported_entries)?;
        entries.extend(imported_entries);

        let mut identities = HashMap::<(String, String), u32>::new();
        for entry in entries {
            identities
                .entry((entry.phrase, entry.pinyin))
                .and_modify(|frequency| *frequency = (*frequency).max(entry.frequency))
                .or_insert(entry.frequency);
        }
        let entries = identities
            .into_iter()
            .map(|((phrase, pinyin), frequency)| LexiconEntry {
                phrase,
                pinyin,
                frequency,
            })
            .collect();
        Ok(Self::from_entries(entries))
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

        Ok(Self::from_entries(entries))
    }

    fn from_entries(entries: Vec<LexiconEntry>) -> Self {
        let compact_index = build_compact_index(&entries);
        let initial_index = build_initial_index(&entries);
        let nine_key_index = build_nine_key_index(&entries);
        let max_compact_pinyin_chars = compact_index
            .iter()
            .map(|entry| entry.compact_pinyin.chars().count())
            .max()
            .unwrap_or_default();
        let max_initial_chars = initial_index
            .iter()
            .map(|entry| entry.initials.chars().count())
            .max()
            .unwrap_or_default();
        let max_nine_key_chars = nine_key_index
            .iter()
            .map(|entry| entry.digits.len())
            .max()
            .unwrap_or_default();

        Self {
            entries,
            compact_index,
            initial_index,
            nine_key_index,
            max_compact_pinyin_chars,
            max_initial_chars,
            max_nine_key_chars,
        }
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
        let mut cache = ContinuousDecodeCache::default();
        self.lookup_with_context_cached(
            raw_input,
            parses,
            previous_context,
            transition_score,
            &mut cache,
        )
    }

    // Path scores are reusable only while the session context and transition snapshot stay stable.
    pub(crate) fn lookup_with_context_cached(
        &self,
        raw_input: &str,
        parses: &[PinyinParse],
        previous_context: Option<&str>,
        transition_score: impl Fn(&str, &str) -> f64,
        continuous_cache: &mut ContinuousDecodeCache,
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

        continuous_candidates.extend(self.continuous_candidates_cached(
            raw_input,
            previous_context,
            &transition_score,
            &mut seen,
            continuous_cache,
        ));
        continuous_candidates.extend(self.mixed_exact_candidates(raw_input, &mut seen));
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

    pub fn lookup_nine_key(&self, digits: &str) -> Vec<Candidate> {
        self.lookup_nine_key_with_context(digits, None, |_, _| 0.0)
    }

    pub fn lookup_nine_key_with_context(
        &self,
        digits: &str,
        previous_context: Option<&str>,
        transition_score: impl Fn(&str, &str) -> f64,
    ) -> Vec<Candidate> {
        if !is_valid_nine_key_input(digits) {
            return Vec::new();
        }

        let mut exact_candidates = Vec::new();
        let mut continuous_candidates = Vec::new();
        let mut prefix_candidates = Vec::new();
        let mut seen = HashSet::<String>::new();

        for indexed_entry in &self.nine_key_index[self.nine_key_prefix_range(digits)] {
            let entry = &self.entries[indexed_entry.entry_index];
            if !seen.insert(entry.phrase.clone()) {
                continue;
            }

            let exact_match = indexed_entry.digits == digits;
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

        continuous_candidates.extend(self.continuous_nine_key_candidates(
            digits,
            previous_context,
            &transition_score,
            &mut seen,
        ));
        Ranker::sort_candidates(&mut exact_candidates);
        Ranker::sort_candidates(&mut continuous_candidates);
        Ranker::sort_candidates(&mut prefix_candidates);

        exact_candidates.extend(continuous_candidates);
        exact_candidates.extend(prefix_candidates);
        exact_candidates.truncate(MAX_LOOKUP_CANDIDATES);
        exact_candidates
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

    fn nine_key_prefix_range(&self, prefix: &str) -> std::ops::Range<usize> {
        let upper_bound = compact_prefix_upper_bound(prefix);
        let start = self
            .nine_key_index
            .partition_point(|entry| entry.digits.as_str() < prefix);
        let end = self
            .nine_key_index
            .partition_point(|entry| entry.digits.as_str() < upper_bound.as_str());
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

    fn mixed_exact_candidates(
        &self,
        raw_input: &str,
        seen: &mut HashSet<String>,
    ) -> Vec<Candidate> {
        let normalized = PinyinParser::normalize_raw(raw_input);
        let input_chars = normalized.chars().count();
        if normalized.contains('\'') || !(3..=MAX_MIXED_INPUT_CHARS).contains(&input_chars) {
            return Vec::new();
        }

        let mut candidates = Vec::new();
        for parse in mixed_input_parses(&normalized) {
            let initials = parse
                .tokens
                .iter()
                .filter_map(|token| token.text.chars().next())
                .collect::<String>();
            let start = self
                .initial_index
                .partition_point(|entry| entry.initials.as_str() < initials.as_str());
            let end = self
                .initial_index
                .partition_point(|entry| entry.initials.as_str() <= initials.as_str());

            for indexed_entry in &self.initial_index[start..end] {
                let entry = &self.entries[indexed_entry.entry_index];
                if !mixed_parse_matches_pinyin(&parse, &entry.pinyin)
                    || !seen.insert(entry.phrase.clone())
                {
                    continue;
                }
                candidates.push(
                    Candidate::new(&entry.phrase, &entry.pinyin, CandidateSource::Base)
                        .with_score(Ranker::score(entry.frequency))
                        .with_rank_score(Ranker::score_match(
                            entry.frequency,
                            CandidateMatchKind::Segmented,
                            CandidateSource::Base,
                        )),
                );
            }
        }

        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(MAX_CONTINUOUS_CANDIDATES);
        candidates
    }

    fn continuous_candidates_cached(
        &self,
        raw_input: &str,
        previous_context: Option<&str>,
        transition_score: &impl Fn(&str, &str) -> f64,
        seen: &mut HashSet<String>,
        cache: &mut ContinuousDecodeCache,
    ) -> Vec<Candidate> {
        let Some((compact, forced_boundaries)) = compact_input_with_boundaries(raw_input) else {
            return Vec::new();
        };
        let chars = compact.chars().collect::<Vec<_>>();
        if chars.is_empty() {
            return Vec::new();
        }

        let reused_chars = cache.prepare(&compact, &forced_boundaries, previous_context);
        let max_edge_chars = self.max_compact_pinyin_chars.max(self.max_initial_chars);

        for start in 0..chars.len() {
            if cache.lattice[start].is_empty() {
                continue;
            }

            let end_limit = chars.len().min(start.saturating_add(max_edge_chars));
            let first_unprocessed_end = (start + 1).max(reused_chars + 1);
            if first_unprocessed_end > end_limit {
                continue;
            }

            for end in first_unprocessed_end..=end_limit {
                let compact_edge = chars[start..end].iter().collect::<String>();
                let edges = self.exact_edges_for_mixed_input(
                    &compact_edge,
                    start,
                    end,
                    &forced_boundaries,
                    MAX_CONTINUOUS_OPTIONS_PER_EDGE,
                );
                if edges.is_empty() {
                    continue;
                }

                let previous_paths = cache.lattice[start].clone();
                for previous in previous_paths {
                    for edge in &edges {
                        let entry = edge.entry;
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
                        let (abbreviated_syllables, full_pinyin_chars, abbreviation_score) =
                            match edge.kind {
                                ContinuousEdgeKind::FullPinyin => {
                                    (0, compact_edge.chars().count(), 0.0)
                                }
                                ContinuousEdgeKind::Initials { syllables } => (
                                    syllables,
                                    0,
                                    Ranker::score_continuous_initial_edge(syllables),
                                ),
                            };
                        cache.lattice[end].push(ContinuousPath {
                            text,
                            pinyin,
                            score: previous.score
                                + Ranker::score_continuous_token(
                                    entry.frequency,
                                    entry.phrase.chars().count(),
                                )
                                + transition
                                + abbreviation_score,
                            segments,
                            abbreviated_syllables: previous.abbreviated_syllables
                                + abbreviated_syllables,
                            full_pinyin_chars: previous.full_pinyin_chars + full_pinyin_chars,
                        });
                    }
                }

                sort_continuous_paths(&mut cache.lattice[end], CONTINUOUS_BEAM_WIDTH);
            }
        }

        if chars.len() < 2 {
            return Vec::new();
        }

        let mut complete_paths = cache.lattice[chars.len()].clone();
        sort_continuous_paths(&mut complete_paths, MAX_CONTINUOUS_CANDIDATES);
        let mut candidates = Vec::new();
        for path in &complete_paths {
            if path.segments.len() < 2
                || (path.abbreviated_syllables > 0 && path.full_pinyin_chars < 2)
                || !seen.insert(path.text.clone())
            {
                continue;
            }
            let rank_score = if path.abbreviated_syllables == 0 {
                Ranker::score_continuous_match(path.score)
            } else {
                Ranker::score_mixed_continuous_match(path.score)
            };
            candidates.push(
                Candidate::new(&path.text, &path.pinyin, CandidateSource::Base)
                    .with_score(path.score)
                    .with_rank_score(rank_score)
                    .with_segments(path.segments.clone()),
            );
        }
        candidates
    }

    fn continuous_nine_key_candidates(
        &self,
        digits: &str,
        previous_context: Option<&str>,
        transition_score: &impl Fn(&str, &str) -> f64,
        seen: &mut HashSet<String>,
    ) -> Vec<Candidate> {
        let chars = digits.chars().collect::<Vec<_>>();
        if chars.len() < 2 {
            return Vec::new();
        }

        let mut lattice = vec![Vec::<ContinuousPath>::new(); chars.len() + 1];
        lattice[0].push(ContinuousPath {
            text: String::new(),
            pinyin: String::new(),
            score: 0.0,
            segments: Vec::new(),
            abbreviated_syllables: 0,
            full_pinyin_chars: 0,
        });

        for start in 0..chars.len() {
            if lattice[start].is_empty() {
                continue;
            }

            let end_limit = chars
                .len()
                .min(start.saturating_add(self.max_nine_key_chars));
            for end in (start + 1)..=end_limit {
                let edge = chars[start..end].iter().collect::<String>();
                let entries =
                    self.exact_entries_for_nine_key(&edge, MAX_CONTINUOUS_OPTIONS_PER_EDGE);
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
                            abbreviated_syllables: 0,
                            full_pinyin_chars: previous.full_pinyin_chars,
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

    fn exact_edges_for_mixed_input(
        &self,
        compact: &str,
        start: usize,
        end: usize,
        forced_boundaries: &HashSet<usize>,
        limit: usize,
    ) -> Vec<ContinuousEdge<'_>> {
        let mut edges = Vec::new();
        let mut seen = HashSet::<&str>::new();

        for entry in self.exact_entries_for_compact(compact, start, end, forced_boundaries, limit) {
            if seen.insert(entry.phrase.as_str()) {
                edges.push(ContinuousEdge {
                    entry,
                    kind: ContinuousEdgeKind::FullPinyin,
                });
            }
        }

        for entry in self.exact_entries_for_initials(compact, limit) {
            if seen.insert(entry.phrase.as_str()) {
                edges.push(ContinuousEdge {
                    entry,
                    kind: ContinuousEdgeKind::Initials {
                        syllables: entry.pinyin.split_whitespace().count(),
                    },
                });
            }
        }

        edges.sort_by(|left, right| {
            continuous_edge_priority(left.kind)
                .cmp(&continuous_edge_priority(right.kind))
                .then_with(|| right.entry.frequency.cmp(&left.entry.frequency))
                .then_with(|| left.entry.phrase.cmp(&right.entry.phrase))
                .then_with(|| left.entry.pinyin.cmp(&right.entry.pinyin))
        });
        edges.truncate(limit);
        edges
    }

    fn exact_entries_for_initials(&self, initials: &str, limit: usize) -> Vec<&LexiconEntry> {
        let start = self
            .initial_index
            .partition_point(|entry| entry.initials.as_str() < initials);
        let end = self
            .initial_index
            .partition_point(|entry| entry.initials.as_str() <= initials);
        let mut entries = Vec::new();
        let mut seen = HashSet::<&str>::new();

        for indexed_entry in &self.initial_index[start..end] {
            let entry = &self.entries[indexed_entry.entry_index];
            if seen.insert(entry.phrase.as_str()) {
                entries.push(entry);
                if entries.len() == limit {
                    break;
                }
            }
        }
        entries
    }

    fn exact_entries_for_nine_key(&self, digits: &str, limit: usize) -> Vec<&LexiconEntry> {
        let mut entries = Vec::new();
        let mut seen = HashSet::<&str>::new();
        for indexed_entry in &self.nine_key_index[self.nine_key_prefix_range(digits)] {
            if indexed_entry.digits != digits {
                continue;
            }
            let entry = &self.entries[indexed_entry.entry_index];
            if seen.insert(entry.phrase.as_str()) {
                entries.push(entry);
            }
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
            .then_with(|| {
                entries[right.entry_index]
                    .frequency
                    .cmp(&entries[left.entry_index].frequency)
            })
            .then_with(|| {
                entries[left.entry_index]
                    .phrase
                    .cmp(&entries[right.entry_index].phrase)
            })
            .then_with(|| {
                entries[left.entry_index]
                    .pinyin
                    .cmp(&entries[right.entry_index].pinyin)
            })
            .then_with(|| left.entry_index.cmp(&right.entry_index))
    });
    index
}

fn build_nine_key_index(entries: &[LexiconEntry]) -> Vec<NineKeyLexiconIndexEntry> {
    let mut index = entries
        .iter()
        .enumerate()
        .filter_map(|(entry_index, entry)| {
            let digits = pinyin_to_nine_key(&entry.pinyin);
            (!digits.is_empty()).then_some(NineKeyLexiconIndexEntry {
                digits,
                entry_index,
            })
        })
        .collect::<Vec<_>>();
    index.sort_by(|left, right| {
        left.digits
            .cmp(&right.digits)
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

fn mixed_input_parses(input: &str) -> Vec<MixedInputParse> {
    let chars = input.chars().collect::<Vec<_>>();
    if chars.len() > MAX_MIXED_INPUT_CHARS {
        return Vec::new();
    }

    let mut lattice = vec![Vec::<MixedInputParse>::new(); chars.len() + 1];
    lattice[0].push(MixedInputParse {
        tokens: Vec::new(),
        abbreviated_syllables: 0,
        full_pinyin_chars: 0,
    });

    for start in 0..chars.len() {
        let previous_parses = std::mem::take(&mut lattice[start]);
        if previous_parses.is_empty() {
            continue;
        }

        let initial = chars[start].to_string();
        for previous in &previous_parses {
            let mut next = previous.clone();
            next.tokens.push(MixedInputToken {
                text: initial.clone(),
                abbreviated: true,
            });
            next.abbreviated_syllables += 1;
            lattice[start + 1].push(next);
        }
        sort_mixed_input_parses(&mut lattice[start + 1]);

        let end_limit = chars
            .len()
            .min(start.saturating_add(MAX_PINYIN_SYLLABLE_CHARS));
        for end in (start + 2)..=end_limit {
            let syllable = chars[start..end].iter().collect::<String>();
            if !is_legal_syllable(&syllable) {
                continue;
            }
            for previous in &previous_parses {
                let mut next = previous.clone();
                next.tokens.push(MixedInputToken {
                    text: syllable.clone(),
                    abbreviated: false,
                });
                next.full_pinyin_chars += syllable.chars().count();
                lattice[end].push(next);
            }
            sort_mixed_input_parses(&mut lattice[end]);
        }
    }

    let mut parses = lattice.pop().unwrap_or_default();
    parses.retain(|parse| parse.abbreviated_syllables > 0 && parse.full_pinyin_chars >= 2);
    sort_mixed_input_parses(&mut parses);
    parses
}

fn sort_mixed_input_parses(parses: &mut Vec<MixedInputParse>) {
    parses.sort_unstable_by(|left, right| {
        left.abbreviated_syllables
            .cmp(&right.abbreviated_syllables)
            .then_with(|| right.full_pinyin_chars.cmp(&left.full_pinyin_chars))
            .then_with(|| left.tokens.len().cmp(&right.tokens.len()))
            .then_with(|| mixed_tokens_cmp(&left.tokens, &right.tokens))
    });
    parses.dedup_by(|left, right| left.tokens == right.tokens);
    parses.truncate(MAX_MIXED_INPUT_PARSES);
}

fn mixed_tokens_cmp(left: &[MixedInputToken], right: &[MixedInputToken]) -> Ordering {
    for (left_token, right_token) in left.iter().zip(right) {
        let ordering = left_token
            .abbreviated
            .cmp(&right_token.abbreviated)
            .then_with(|| left_token.text.cmp(&right_token.text));
        if ordering != Ordering::Equal {
            return ordering;
        }
    }
    left.len().cmp(&right.len())
}

fn mixed_parse_matches_pinyin(parse: &MixedInputParse, pinyin: &str) -> bool {
    let syllables = pinyin.split_whitespace().collect::<Vec<_>>();
    parse.tokens.len() == syllables.len()
        && parse.tokens.iter().zip(syllables).all(|(token, syllable)| {
            if token.abbreviated {
                syllable.starts_with(&token.text)
            } else {
                syllable == token.text
            }
        })
}

fn continuous_edge_priority(kind: ContinuousEdgeKind) -> u8 {
    match kind {
        ContinuousEdgeKind::FullPinyin => 0,
        ContinuousEdgeKind::Initials { .. } => 1,
    }
}

fn common_prefix_chars(left: &str, right: &str) -> usize {
    left.chars()
        .zip(right.chars())
        .take_while(|(left, right)| left == right)
        .count()
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mixed_input_parser_stops_at_its_dedicated_length_limit() {
        assert!(!mixed_input_parses("wojtxqcfjttqbcsj").is_empty());
        assert!(mixed_input_parses("wojtxqcfjttqbcsja").is_empty());
    }

    #[test]
    fn continuous_cache_reuses_prefixes_and_invalidates_changed_boundaries_or_context() {
        let lexicon = Lexicon::from_tsv(
            "我\two\t100000\n今天\tjin tian\t90000\n今\tjin\t80000\n天\ttian\t70000\n",
        )
        .expect("test lexicon loads");
        let parser = PinyinParser;
        let mut cache = ContinuousDecodeCache::default();

        let parses = parser.parse("wo");
        lexicon.lookup_with_context_cached("wo", &parses, None, |_, _| 0.0, &mut cache);
        assert_eq!(cache.last_reused_chars, 0);

        let parses = parser.parse("woj");
        lexicon.lookup_with_context_cached("woj", &parses, None, |_, _| 0.0, &mut cache);
        assert_eq!(cache.last_reused_chars, 2);

        let parses = parser.parse("wojt");
        let candidates =
            lexicon.lookup_with_context_cached("wojt", &parses, None, |_, _| 0.0, &mut cache);
        assert_eq!(cache.last_reused_chars, 3);
        assert_eq!(
            candidates.first().map(|candidate| candidate.text.as_str()),
            Some("我今天")
        );

        let parses = parser.parse("wo'jt");
        lexicon.lookup_with_context_cached("wo'jt", &parses, None, |_, _| 0.0, &mut cache);
        assert_eq!(cache.last_reused_chars, 2);

        let parses = parser.parse("woj");
        lexicon.lookup_with_context_cached("woj", &parses, Some("前文"), |_, _| 0.0, &mut cache);
        assert_eq!(cache.last_reused_chars, 0);
    }
}
