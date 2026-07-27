use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CandidateSource {
    Base,
    User,
    Prediction,
    Symbol,
    Raw,
}

impl fmt::Display for CandidateSource {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let source = match self {
            Self::Base => "base",
            Self::User => "user",
            Self::Prediction => "prediction",
            Self::Symbol => "symbol",
            Self::Raw => "raw",
        };
        formatter.write_str(source)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Candidate {
    pub id: String,
    pub text: String,
    pub pinyin: String,
    pub score: f64,
    pub rank_score: f64,
    pub source: CandidateSource,
    pub comment: Option<String>,
    pub segments: Vec<CandidateSegment>,
    pub correction: Option<CandidateCorrection>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CandidateSegment {
    pub text: String,
    pub pinyin: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CandidateCorrectionKind {
    CommonConfusion,
    DuplicateLetter,
    MissingMedial,
    AdjacentKey,
    TransposedLetters,
    NineKeyAdjacentDigit,
    NineKeyExtraDigit,
    NineKeyMissingDigit,
    NineKeyTransposedDigits,
    FuzzyPinyin,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CandidateCorrectionConfidence {
    Exact,
    Probable,
    Weak,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CandidateCorrection {
    pub kind: CandidateCorrectionKind,
    pub confidence: CandidateCorrectionConfidence,
    pub edit_distance: u8,
}

impl CandidateCorrection {
    pub const fn ai_lite_score(self) -> u16 {
        match self.confidence {
            CandidateCorrectionConfidence::Exact => 1_000,
            CandidateCorrectionConfidence::Probable => 750,
            CandidateCorrectionConfidence::Weak => 450,
        }
    }
}

impl CandidateCorrectionKind {
    pub const fn is_fuzzy_pinyin(self) -> bool {
        matches!(self, Self::FuzzyPinyin)
    }
}

impl Candidate {
    pub fn new(
        text: impl Into<String>,
        pinyin: impl Into<String>,
        source: CandidateSource,
    ) -> Self {
        let text = text.into();
        let pinyin = pinyin.into();
        Self {
            id: format!("{source}:{pinyin}:{text}"),
            text,
            pinyin,
            score: 0.0,
            rank_score: 0.0,
            source,
            comment: None,
            segments: Vec::new(),
            correction: None,
        }
    }

    pub fn with_score(mut self, score: f64) -> Self {
        self.score = score;
        self.rank_score = score;
        self
    }

    pub fn with_rank_score(mut self, rank_score: f64) -> Self {
        self.rank_score = rank_score;
        self
    }

    pub fn with_segments(mut self, segments: Vec<CandidateSegment>) -> Self {
        self.segments = segments;
        self
    }

    pub fn with_correction(mut self, correction: CandidateCorrection) -> Self {
        self.correction = Some(correction);
        self
    }
}

pub(crate) fn promote_correction_candidates(
    mut candidates: Vec<Candidate>,
    candidate_page_size: usize,
    maximum_visible_corrections: usize,
) -> Vec<Candidate> {
    let correction_count = candidates
        .iter()
        .filter(|candidate| candidate.correction.is_some())
        .count();
    if correction_count == 0 {
        return candidates;
    }

    let already_visible = candidates
        .iter()
        .take(candidate_page_size)
        .filter(|candidate| candidate.correction.is_some())
        .count();
    let promote_count = maximum_visible_corrections.saturating_sub(already_visible);
    if promote_count == 0 {
        return candidates;
    }

    let correction_indices = candidates
        .iter()
        .enumerate()
        .skip(candidate_page_size)
        .filter_map(|(index, candidate)| candidate.correction.is_some().then_some(index))
        .take(promote_count)
        .collect::<Vec<_>>();
    let mut promoted = Vec::with_capacity(correction_indices.len());
    for index in correction_indices.into_iter().rev() {
        promoted.push(candidates.remove(index));
    }
    promoted.reverse();

    let insertion_index = candidate_page_size
        .saturating_sub(promoted.len())
        .min(candidates.len());
    candidates.splice(insertion_index..insertion_index, promoted);
    candidates
}
