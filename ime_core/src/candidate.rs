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
    pub source: CandidateSource,
    pub comment: Option<String>,
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
            source,
            comment: None,
        }
    }

    pub fn with_score(mut self, score: f64) -> Self {
        self.score = score;
        self
    }
}
