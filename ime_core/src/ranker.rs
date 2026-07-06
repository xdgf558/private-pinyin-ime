use crate::candidate::Candidate;

pub struct Ranker;

impl Ranker {
    pub fn score(base_frequency: u32) -> f64 {
        base_frequency as f64
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
