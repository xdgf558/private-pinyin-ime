use std::fmt;

pub type ImeResult<T> = Result<T, ImeError>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImeError {
    InvalidLexiconFormat,
    InvalidLexiconFrequency,
    InvalidSettingsValue,
    MissingLexiconField,
    SettingsIo,
    SettingsParse,
    UserLexiconDatabase,
}

impl ImeError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidLexiconFormat => "INVALID_LEXICON_FORMAT",
            Self::InvalidLexiconFrequency => "INVALID_LEXICON_FREQUENCY",
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
