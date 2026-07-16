#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
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
