use crate::candidate::{Candidate, CandidateSource};
use crate::error::{ImeError, ImeResult};
use crate::ranker::Ranker;

const EMBEDDED_BIGRAM: &str = include_str!("../assets/bigram.tsv");

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BigramEntry {
    pub left: String,
    pub right: String,
    pub frequency: u32,
}

#[derive(Debug, Clone, Default)]
pub struct Predictor {
    bigrams: Vec<BigramEntry>,
}

impl Predictor {
    pub fn load_embedded() -> ImeResult<Self> {
        Self::from_tsv(EMBEDDED_BIGRAM)
    }

    pub fn from_tsv(tsv: &str) -> ImeResult<Self> {
        let mut bigrams = Vec::new();

        for (line_index, line) in tsv.lines().enumerate() {
            if line.trim().is_empty() {
                continue;
            }

            if line_index == 0 && line == "left\tright\tfrequency" {
                continue;
            }

            let mut fields = line.split('\t');
            let left = fields
                .next()
                .filter(|value| !value.is_empty())
                .ok_or(ImeError::MissingLexiconField)?;
            let right = fields
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

            bigrams.push(BigramEntry {
                left: left.to_owned(),
                right: right.to_owned(),
                frequency,
            });
        }

        Ok(Self { bigrams })
    }

    pub fn predict_next(&self, context_tokens: &[String]) -> Vec<Candidate> {
        let Some(last_token) = context_tokens.last() else {
            return Vec::new();
        };

        let mut candidates = self
            .bigrams
            .iter()
            .filter(|entry| entry.left == *last_token)
            .map(|entry| {
                Candidate::new(&entry.right, "", CandidateSource::Prediction)
                    .with_score(Ranker::score(entry.frequency))
            })
            .collect::<Vec<_>>();
        Ranker::sort_candidates(&mut candidates);
        candidates.truncate(50);
        candidates
    }
}
