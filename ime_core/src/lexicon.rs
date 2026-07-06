use std::collections::HashSet;

use crate::candidate::{Candidate, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::pinyin_parser::{PinyinParse, PinyinParser};
use crate::ranker::Ranker;

const EMBEDDED_BASE_LEXICON: &str = include_str!("../assets/base_lexicon_sample.tsv");

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LexiconEntry {
    pub phrase: String,
    pub pinyin: String,
    pub frequency: u32,
}

#[derive(Debug, Clone, Default)]
pub struct Lexicon {
    entries: Vec<LexiconEntry>,
}

impl Lexicon {
    pub fn load_embedded() -> ImeResult<Self> {
        Self::from_tsv(EMBEDDED_BASE_LEXICON)
    }

    pub fn from_tsv(tsv: &str) -> ImeResult<Self> {
        let mut entries = Vec::new();

        for line in tsv.lines().skip(1) {
            if line.trim().is_empty() {
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

        Ok(Self { entries })
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
        let mut seen = HashSet::new();

        for entry in &self.entries {
            let exact_match = exact_pinyins.contains(&entry.pinyin);
            let prefix_match = compact_pinyin(&entry.pinyin).starts_with(&normalized_input);

            if !(exact_match || prefix_match) || !seen.insert(entry.phrase.clone()) {
                continue;
            }

            let score = Ranker::score(entry.frequency, exact_match);
            candidates.push(
                Candidate::new(&entry.phrase, &entry.pinyin, CandidateSource::Base)
                    .with_score(score),
            );
        }

        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(50);
        candidates
    }
}

fn compact_pinyin(pinyin: &str) -> String {
    pinyin.split_whitespace().collect::<String>()
}
