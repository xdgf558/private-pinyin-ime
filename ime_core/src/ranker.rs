use crate::candidate::{Candidate, CandidateSource};

const MATCH_TIER_WEIGHT: f64 = 10_000_000_000.0;
const USER_SHORT_PREDICTION_BOOST: f64 = 2_000_000_000.0;
const USER_PREDICTION_BOOST: f64 = 1_000_000_000.0;
const USER_SOURCE_BOOST: f64 = 100_000_000.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CandidateMatchKind {
    Exact,
    Segmented,
    InitialExact,
    Prefix,
    InitialPrefix,
}

pub struct Ranker;

impl Ranker {
    pub fn score(base_frequency: u32) -> f64 {
        base_frequency as f64
    }

    pub fn score_user_prediction(base_frequency: u32) -> f64 {
        USER_PREDICTION_BOOST + Self::score(base_frequency)
    }

    pub fn score_user_short_prediction(base_frequency: u32) -> f64 {
        USER_SHORT_PREDICTION_BOOST + Self::score(base_frequency)
    }

    pub fn score_match(
        base_frequency: u32,
        match_kind: CandidateMatchKind,
        source: CandidateSource,
    ) -> f64 {
        let match_tier = match match_kind {
            CandidateMatchKind::Exact => 3.0,
            CandidateMatchKind::Segmented => 2.0,
            CandidateMatchKind::InitialExact => 1.5,
            CandidateMatchKind::Prefix => 1.0,
            CandidateMatchKind::InitialPrefix => 0.8,
        };
        let source_boost = match source {
            CandidateSource::User => USER_SOURCE_BOOST,
            _ => 0.0,
        };

        match_tier * MATCH_TIER_WEIGHT + source_boost + Self::score(base_frequency)
    }

    pub fn sort_candidates(candidates: &mut [Candidate]) {
        candidates.sort_by(|left, right| {
            right
                .rank_score
                .total_cmp(&left.rank_score)
                .then_with(|| left.text.cmp(&right.text))
                .then_with(|| left.pinyin.cmp(&right.pinyin))
        });
    }
}
