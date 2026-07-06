use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{ImeError, ImeResult};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ImeMode {
    #[serde(rename = "Chinese", alias = "chinese")]
    Chinese,
    #[serde(rename = "English", alias = "english")]
    English,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ToggleKey {
    #[serde(rename = "Shift", alias = "shift")]
    Shift,
    #[serde(
        rename = "CtrlSpace",
        alias = "Ctrl Space",
        alias = "Ctrl+Space",
        alias = "ctrl_space"
    )]
    CtrlSpace,
    #[serde(rename = "CapsLock", alias = "Caps Lock", alias = "caps_lock")]
    CapsLock,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct FuzzyPinyinSettings {
    pub zh_z: bool,
    pub ch_c: bool,
    pub sh_s: bool,
    pub n_l: bool,
    pub an_ang: bool,
    pub en_eng: bool,
    pub in_ing: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct ImeSettings {
    pub default_mode: ImeMode,
    pub toggle_key: ToggleKey,
    pub candidate_page_size: usize,
    pub enable_prediction: bool,
    pub enable_user_learning: bool,
    pub strict_privacy_mode: bool,
    pub user_lexicon_path: Option<PathBuf>,
    pub fuzzy_pinyin: FuzzyPinyinSettings,
    pub theme: String,
    pub candidate_font_size: u16,
}

impl ImeSettings {
    pub fn from_json_file(path: impl AsRef<Path>) -> ImeResult<Self> {
        let contents = fs::read_to_string(path).map_err(|_| ImeError::SettingsIo)?;
        Self::from_json_str(&contents)
    }

    pub fn from_json_file_or_default(path: impl AsRef<Path>) -> Self {
        Self::from_json_file(path).unwrap_or_default()
    }

    pub fn from_json_str(contents: &str) -> ImeResult<Self> {
        let mut settings: Self =
            serde_json::from_str(contents).map_err(|_| ImeError::SettingsParse)?;
        settings.normalize()?;
        Ok(settings)
    }

    pub fn write_json_file(&self, path: impl AsRef<Path>) -> ImeResult<()> {
        let path = path.as_ref();
        let mut settings = self.clone();
        settings.normalize()?;

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|_| ImeError::SettingsIo)?;
        }

        let temp_path = path.with_extension("tmp");
        let serialized =
            serde_json::to_string_pretty(&settings).map_err(|_| ImeError::SettingsParse)?;
        let mut file = fs::File::create(&temp_path).map_err(|_| ImeError::SettingsIo)?;
        file.write_all(serialized.as_bytes())
            .map_err(|_| ImeError::SettingsIo)?;
        file.write_all(b"\n").map_err(|_| ImeError::SettingsIo)?;
        file.sync_all().map_err(|_| ImeError::SettingsIo)?;
        drop(file);
        if path.exists() {
            fs::remove_file(path).map_err(|_| ImeError::SettingsIo)?;
        }
        fs::rename(&temp_path, path).map_err(|_| ImeError::SettingsIo)?;
        Ok(())
    }

    fn normalize(&mut self) -> ImeResult<()> {
        if self.candidate_page_size == 0 || self.candidate_font_size == 0 {
            return Err(ImeError::InvalidSettingsValue);
        }

        if self.theme.trim().is_empty() {
            self.theme = Self::default().theme;
        }

        if self.strict_privacy_mode {
            self.enable_user_learning = false;
        }

        Ok(())
    }
}

impl Default for ImeSettings {
    fn default() -> Self {
        Self {
            default_mode: ImeMode::Chinese,
            toggle_key: ToggleKey::Shift,
            candidate_page_size: 5,
            enable_prediction: true,
            enable_user_learning: true,
            strict_privacy_mode: false,
            user_lexicon_path: None,
            fuzzy_pinyin: FuzzyPinyinSettings::default(),
            theme: "system".to_owned(),
            candidate_font_size: 14,
        }
    }
}
