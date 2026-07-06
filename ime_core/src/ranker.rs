use crate::candidate::Candidate;

pub struct Ranker;

impl Ranker {
    pub fn score(base_frequency: u32, exact_match: bool) -> f64 {
        let exact_bonus = if exact_match { 1_000_000.0 } else { 0.0 };
        let prefix_penalty = if exact_match { 0.0 } else { 100_000.0 };
        base_frequency as f64 + exact_bonus - prefix_penalty
    }

    pub fn sort_candidates(candidates: &mut [Candidate]) {
        candidates.sort_by(|left, right| {
            right
                .score
                .total_cmp(&left.score)
                .then_with(|| left.text.cmp(&right.text))
                .then_with(|| left.pinyin.cmp(&right.pinyin))
        });
    }
}
