#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Modifiers {
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
    pub meta: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyCode {
    Character(char),
    Digit(u8),
    NineKeyDigit(u8),
    Space,
    Enter,
    Backspace,
    Escape,
    Shift,
    CtrlSpace,
    CapsLock,
    Comma,
    Period,
    Minus,
    Equal,
    Apostrophe,
    Semicolon,
    PageUp,
    PageDown,
    ArrowUp,
    ArrowDown,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyEvent {
    pub key_code: KeyCode,
    pub text: String,
    pub modifiers: Modifiers,
    pub is_repeat: bool,
    pub timestamp_ms: i64,
}

impl KeyEvent {
    pub fn new(key_code: KeyCode) -> Self {
        Self {
            key_code,
            text: String::new(),
            modifiers: Modifiers::default(),
            is_repeat: false,
            timestamp_ms: 0,
        }
    }

    pub fn from_char(ch: char) -> Self {
        let key_code = match ch {
            'a'..='z' | 'A'..='Z' => KeyCode::Character(ch.to_ascii_lowercase()),
            '0'..='9' => KeyCode::Digit(ch.to_digit(10).unwrap_or_default() as u8),
            ' ' => KeyCode::Space,
            '\n' | '\r' => KeyCode::Enter,
            ',' => KeyCode::Comma,
            '.' => KeyCode::Period,
            '-' => KeyCode::Minus,
            '=' => KeyCode::Equal,
            '\'' => KeyCode::Apostrophe,
            ';' => KeyCode::Semicolon,
            _ => KeyCode::Unknown,
        };

        Self {
            key_code,
            text: ch.to_string(),
            modifiers: Modifiers::default(),
            is_repeat: false,
            timestamp_ms: 0,
        }
    }
}
