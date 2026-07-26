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
