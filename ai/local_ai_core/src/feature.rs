use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AiFeature {
    CandidateRerank,
    PinyinCorrection,
    MixedEnglishTermPreservation,
    ShortCompletion,
    RewriteFormal,
    RewritePolite,
    RewriteShort,
    RewriteCasual,
    TranslateZhEn,
    TranslateEnZh,
    UserLexiconCleanupSuggest,
}

impl AiFeature {
    pub const ALL: [Self; 11] = [
        Self::CandidateRerank,
        Self::PinyinCorrection,
        Self::MixedEnglishTermPreservation,
        Self::ShortCompletion,
        Self::RewriteFormal,
        Self::RewritePolite,
        Self::RewriteShort,
        Self::RewriteCasual,
        Self::TranslateZhEn,
        Self::TranslateEnZh,
        Self::UserLexiconCleanupSuggest,
    ];

    pub const fn is_lite(self) -> bool {
        matches!(
            self,
            Self::CandidateRerank
                | Self::PinyinCorrection
                | Self::MixedEnglishTermPreservation
                | Self::UserLexiconCleanupSuggest
        )
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::CandidateRerank => "candidate_rerank",
            Self::PinyinCorrection => "pinyin_correction",
            Self::MixedEnglishTermPreservation => "mixed_english_term_preservation",
            Self::ShortCompletion => "short_completion",
            Self::RewriteFormal => "rewrite_formal",
            Self::RewritePolite => "rewrite_polite",
            Self::RewriteShort => "rewrite_short",
            Self::RewriteCasual => "rewrite_casual",
            Self::TranslateZhEn => "translate_zh_en",
            Self::TranslateEnZh => "translate_en_zh",
            Self::UserLexiconCleanupSuggest => "user_lexicon_cleanup_suggest",
        }
    }

    pub const fn requires_writer(self) -> bool {
        !self.is_lite()
    }

    pub const fn requires_explicit_user_action(self) -> bool {
        matches!(
            self,
            Self::RewriteFormal
                | Self::RewritePolite
                | Self::RewriteShort
                | Self::RewriteCasual
                | Self::TranslateZhEn
                | Self::TranslateEnZh
                | Self::UserLexiconCleanupSuggest
        )
    }
}
