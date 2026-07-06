use crate::syllable::{is_legal_syllable, is_syllable_prefix, Syllable};

const MAX_SYLLABLE_LEN: usize = 6;
const MAX_PARSE_RESULTS: usize = 8;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PinyinParse {
    pub syllables: Vec<Syllable>,
    pub coverage: usize,
    pub penalty: u32,
}

impl PinyinParse {
    pub fn empty() -> Self {
        Self {
            syllables: Vec::new(),
            coverage: 0,
            penalty: 0,
        }
    }

    pub fn is_complete(&self) -> bool {
        self.syllables.iter().all(|syllable| !syllable.is_prefix)
    }

    pub fn pinyin_string(&self) -> String {
        self.syllables
            .iter()
            .map(|syllable| syllable.text.as_str())
            .collect::<Vec<_>>()
            .join(" ")
    }

    pub fn syllable_texts(&self) -> Vec<String> {
        self.syllables
            .iter()
            .map(|syllable| syllable.text.clone())
            .collect()
    }
}

pub fn compact_pinyin(pinyin: &str) -> String {
    pinyin.split_whitespace().collect::<String>()
}

pub fn compact_prefix_upper_bound(prefix: &str) -> String {
    // Safe for normalized pinyin keys; `char::MAX` must remain outside the indexed alphabet.
    debug_assert!(!prefix.contains(char::MAX));
    let mut upper_bound = String::with_capacity(prefix.len() + 4);
    upper_bound.push_str(prefix);
    upper_bound.push(char::MAX);
    upper_bound
}

#[derive(Debug, Clone, Default)]
pub struct PinyinParser;

impl PinyinParser {
    pub fn normalize_raw(raw_input: &str) -> String {
        raw_input
            .trim()
            .to_lowercase()
            .chars()
            .filter_map(|ch| match ch {
                'v' => Some('ü'),
                ch if ch.is_ascii_alphabetic() || ch == '\'' || ch == 'ü' => Some(ch),
                _ => None,
            })
            .collect()
    }

    pub fn parse(&self, raw_input: &str) -> Vec<PinyinParse> {
        let normalized = Self::normalize_raw(raw_input);
        if normalized.is_empty() {
            return Vec::new();
        }

        if normalized.contains('\'') {
            return self.parse_with_boundaries(&normalized);
        }

        self.parse_segment(&normalized)
    }

    fn parse_with_boundaries(&self, normalized: &str) -> Vec<PinyinParse> {
        let mut combined = vec![PinyinParse::empty()];

        for segment in normalized.split('\'') {
            if segment.is_empty() {
                return Vec::new();
            }

            let segment_parses = self.parse_segment(segment);
            if segment_parses.is_empty() {
                return Vec::new();
            }

            let mut next = Vec::new();
            for prefix in &combined {
                for segment_parse in segment_parses.iter().take(MAX_PARSE_RESULTS) {
                    let mut parse = prefix.clone();
                    parse.coverage += segment_parse.coverage;
                    parse.penalty += segment_parse.penalty;
                    parse.syllables.extend(segment_parse.syllables.clone());
                    next.push(parse);
                }
            }
            combined = sorted_limited(next);
        }

        combined
    }

    fn parse_segment(&self, segment: &str) -> Vec<PinyinParse> {
        let chars = segment.chars().collect::<Vec<_>>();
        let len = chars.len();
        let mut dp = vec![Vec::<PinyinParse>::new(); len + 1];
        dp[0].push(PinyinParse::empty());

        for start in 0..len {
            if dp[start].is_empty() {
                continue;
            }

            let end_limit = len.min(start + MAX_SYLLABLE_LEN);
            for end in (start + 1)..=end_limit {
                let token = chars[start..end].iter().collect::<String>();
                let is_full = is_legal_syllable(&token);
                let is_prefix = end == len && !is_full && is_syllable_prefix(&token);

                if !is_full && !is_prefix {
                    continue;
                }

                let edge_penalty = if is_prefix { 5 } else { 0 };
                let previous_paths = dp[start].clone();
                for previous in previous_paths {
                    let mut next = previous;
                    next.coverage += token.chars().count();
                    next.penalty += edge_penalty;
                    next.syllables.push(Syllable::new(token.clone(), is_prefix));
                    dp[end].push(next);
                }

                dp[end] = sorted_limited(dp[end].clone());
            }
        }

        sorted_limited(dp[len].clone())
    }
}

fn sorted_limited(mut parses: Vec<PinyinParse>) -> Vec<PinyinParse> {
    parses.sort_by(|left, right| {
        left.penalty
            .cmp(&right.penalty)
            .then_with(|| right.coverage.cmp(&left.coverage))
            .then_with(|| left.syllables.len().cmp(&right.syllables.len()))
            .then_with(|| left.pinyin_string().cmp(&right.pinyin_string()))
    });
    parses.dedup_by(|left, right| left.pinyin_string() == right.pinyin_string());
    parses.truncate(MAX_PARSE_RESULTS);
    parses
}
