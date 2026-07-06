#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImeMode {
    Chinese,
    English,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToggleKey {
    Shift,
    CtrlSpace,
    CapsLock,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct FuzzyPinyinSettings {
    pub zh_z: bool,
    pub ch_c: bool,
    pub sh_s: bool,
    pub n_l: bool,
    pub an_ang: bool,
    pub en_eng: bool,
    pub in_ing: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImeSettings {
    pub default_mode: ImeMode,
    pub toggle_key: ToggleKey,
    pub candidate_page_size: usize,
    pub enable_prediction: bool,
    pub enable_user_learning: bool,
    pub strict_privacy_mode: bool,
    pub fuzzy_pinyin: FuzzyPinyinSettings,
    pub theme: String,
    pub candidate_font_size: u16,
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
            fuzzy_pinyin: FuzzyPinyinSettings::default(),
            theme: "system".to_owned(),
            candidate_font_size: 14,
        }
    }
}
