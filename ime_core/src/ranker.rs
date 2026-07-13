use crate::candidate::{Candidate, CandidateSource};

const MATCH_TIER_WEIGHT: f64 = 10_000_000_000.0;
const USER_TRIGRAM_PREDICTION_BOOST: f64 = 3_000_000_000.0;
const USER_SHORT_PREDICTION_BOOST: f64 = 2_000_000_000.0;
const USER_PREDICTION_BOOST: f64 = 1_000_000_000.0;
const USER_SOURCE_BOOST: f64 = 100_000_000.0;
const CONTINUOUS_UNIGRAM_NORMALIZER: f64 = 13.0;
const CONTINUOUS_PHRASE_CHAR_BONUS: f64 = 1.5;
const BASE_TRANSITION_WEIGHT: f64 = 0.8;
const USER_TRANSITION_BOOST: f64 = 6.0;
const USER_TRANSITION_WEIGHT: f64 = 2.0;

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

    pub fn score_weight(weight: f64) -> f64 {
        weight.max(0.0)
    }

    pub fn score_user_prediction(base_frequency: u32) -> f64 {
        Self::score_user_prediction_weight(f64::from(base_frequency))
    }

    pub fn score_user_prediction_weight(weight: f64) -> f64 {
        learned_score(USER_PREDICTION_BOOST, weight)
    }

    pub fn score_user_short_prediction(base_frequency: u32) -> f64 {
        Self::score_user_short_prediction_weight(f64::from(base_frequency))
    }

    pub fn score_user_short_prediction_weight(weight: f64) -> f64 {
        learned_score(USER_SHORT_PREDICTION_BOOST, weight)
    }

    pub fn score_user_trigram_prediction_weight(weight: f64) -> f64 {
        learned_score(USER_TRIGRAM_PREDICTION_BOOST, weight)
    }

    pub fn score_continuous_token(base_frequency: u32, phrase_chars: usize) -> f64 {
        (f64::from(base_frequency) + 1.0).ln() - CONTINUOUS_UNIGRAM_NORMALIZER
            + phrase_chars.saturating_sub(1) as f64 * CONTINUOUS_PHRASE_CHAR_BONUS
    }

    pub fn score_continuous_transition(base_frequency: u32, user_frequency: u32) -> f64 {
        Self::score_continuous_transition_weight(base_frequency, f64::from(user_frequency))
    }

    pub fn score_continuous_transition_weight(base_frequency: u32, user_weight: f64) -> f64 {
        let base_score = if base_frequency == 0 {
            0.0
        } else {
            (f64::from(base_frequency) + 1.0).ln() * BASE_TRANSITION_WEIGHT
        };
        let user_weight = user_weight.max(0.0);
        let user_score = if user_weight == 0.0 {
            0.0
        } else {
            USER_TRANSITION_BOOST * user_weight.min(1.0)
                + (user_weight + 1.0).ln() * USER_TRANSITION_WEIGHT
        };
        base_score + user_score
    }

    pub fn score_continuous_match(path_score: f64) -> f64 {
        2.0 * MATCH_TIER_WEIGHT + path_score
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

    pub fn score_user_match(weight: f64, match_kind: CandidateMatchKind) -> f64 {
        let match_tier = match match_kind {
            CandidateMatchKind::Exact => 3.0,
            CandidateMatchKind::Segmented => 2.0,
            CandidateMatchKind::InitialExact => 1.5,
            CandidateMatchKind::Prefix => 1.0,
            CandidateMatchKind::InitialPrefix => 0.8,
        };
        let weight = weight.max(0.0);
        match_tier * MATCH_TIER_WEIGHT
            + USER_SOURCE_BOOST * weight.min(1.0)
            + Self::score_weight(weight)
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

fn learned_score(boost: f64, weight: f64) -> f64 {
    let weight = weight.max(0.0);
    boost * weight.min(1.0) + Ranker::score_weight(weight)
}
