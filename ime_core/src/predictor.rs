use crate::candidate::Candidate;

#[derive(Debug, Clone, Default)]
pub struct Predictor;

impl Predictor {
    pub fn predict_next(&self, _context_tokens: &[String]) -> Vec<Candidate> {
        Vec::new()
    }
}
