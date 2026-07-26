use std::fmt;

pub type ImeResult<T> = Result<T, ImeError>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImeError {
    ImportedLexiconIo,
    ImportedLexiconLimit,
    ImportedLexiconNotConfigured,
    ImportedLexiconParse,
    ReviewedLexiconArchive,
    ReviewedLexiconArtifact,
    ReviewedLexiconNotConfigured,
    InvalidLexiconFormat,
    InvalidLexiconFrequency,
    InvalidPinyinCorrectionRules,
    InvalidSettingsValue,
    MissingLexiconField,
    SettingsIo,
    SettingsParse,
    UserLexiconDatabase,
}

impl ImeError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::ImportedLexiconIo => "IMPORTED_LEXICON_IO",
            Self::ImportedLexiconLimit => "IMPORTED_LEXICON_LIMIT",
            Self::ImportedLexiconNotConfigured => "IMPORTED_LEXICON_NOT_CONFIGURED",
            Self::ImportedLexiconParse => "IMPORTED_LEXICON_PARSE",
            Self::ReviewedLexiconArchive => "REVIEWED_LEXICON_ARCHIVE",
            Self::ReviewedLexiconArtifact => "REVIEWED_LEXICON_ARTIFACT",
            Self::ReviewedLexiconNotConfigured => "REVIEWED_LEXICON_NOT_CONFIGURED",
            Self::InvalidLexiconFormat => "INVALID_LEXICON_FORMAT",
            Self::InvalidLexiconFrequency => "INVALID_LEXICON_FREQUENCY",
            Self::InvalidPinyinCorrectionRules => "INVALID_PINYIN_CORRECTION_RULES",
            Self::InvalidSettingsValue => "INVALID_SETTINGS_VALUE",
            Self::MissingLexiconField => "MISSING_LEXICON_FIELD",
            Self::SettingsIo => "SETTINGS_IO",
            Self::SettingsParse => "SETTINGS_PARSE",
            Self::UserLexiconDatabase => "USER_LEXICON_DATABASE",
        }
    }
}

impl fmt::Display for ImeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.code())
    }
}

impl std::error::Error for ImeError {}
