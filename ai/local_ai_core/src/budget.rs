use std::time::{Duration, Instant};

use crate::AiFeature;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AiBudget {
    max_elapsed: Duration,
    max_candidates: usize,
    max_suggestions: usize,
}

impl AiBudget {
    pub const fn new(max_elapsed: Duration, max_candidates: usize, max_suggestions: usize) -> Self {
        Self {
            max_elapsed,
            max_candidates,
            max_suggestions,
        }
    }

    pub const fn for_feature(feature: AiFeature) -> Self {
        match feature {
            AiFeature::CandidateRerank
            | AiFeature::PinyinCorrection
            | AiFeature::MixedEnglishTermPreservation => {
                Self::new(Duration::from_millis(30), 32, 3)
            }
            AiFeature::ShortCompletion => Self::new(Duration::from_millis(800), 9, 3),
            AiFeature::RewriteFormal
            | AiFeature::RewritePolite
            | AiFeature::RewriteShort
            | AiFeature::RewriteCasual
            | AiFeature::TranslateZhEn
            | AiFeature::TranslateEnZh => Self::new(Duration::from_secs(3), 9, 3),
            AiFeature::UserLexiconCleanupSuggest => Self::new(Duration::from_millis(800), 64, 32),
        }
    }

    pub const fn max_elapsed(self) -> Duration {
        self.max_elapsed
    }

    pub const fn max_candidates(self) -> usize {
        self.max_candidates
    }

    pub const fn max_suggestions(self) -> usize {
        self.max_suggestions
    }

    pub const fn is_valid(self) -> bool {
        !self.max_elapsed.is_zero()
            && self.max_candidates > 0
            && self.max_suggestions > 0
            && self.max_suggestions <= self.max_candidates
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AiDeadline {
    issued_at: Instant,
    expires_at: Instant,
}

impl AiDeadline {
    pub fn from_now(timeout: Duration) -> Self {
        Self::from_start(Instant::now(), timeout)
    }

    pub fn from_start(issued_at: Instant, timeout: Duration) -> Self {
        let expires_at = issued_at.checked_add(timeout).unwrap_or(issued_at);
        Self {
            issued_at,
            expires_at,
        }
    }

    pub const fn issued_at(self) -> Instant {
        self.issued_at
    }

    pub const fn expires_at(self) -> Instant {
        self.expires_at
    }

    pub fn is_expired(self) -> bool {
        self.is_expired_at(Instant::now())
    }

    pub fn is_expired_at(self, now: Instant) -> bool {
        now >= self.expires_at
    }

    pub fn remaining_at(self, now: Instant) -> Duration {
        self.expires_at
            .checked_duration_since(now)
            .unwrap_or_default()
    }
}
