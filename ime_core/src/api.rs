use std::sync::Arc;

use crate::candidate::Candidate;
use crate::error::ImeResult;
use crate::key_event::KeyEvent;
use crate::lexicon::Lexicon;
use crate::pinyin_parser::PinyinParser;
use crate::session::InputSession;
use crate::settings::{ImeMode, ImeSettings};

#[derive(Debug, Clone, PartialEq)]
pub struct ImeOutput {
    pub preedit: String,
    pub commit_text: String,
    pub mode: ImeMode,
    pub should_update_preedit: bool,
    pub should_commit: bool,
    pub should_show_candidates: bool,
    pub candidates: Vec<Candidate>,
}

impl ImeOutput {
    pub fn idle(mode: ImeMode) -> Self {
        Self {
            preedit: String::new(),
            commit_text: String::new(),
            mode,
            should_update_preedit: false,
            should_commit: false,
            should_show_candidates: false,
            candidates: Vec::new(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ImeEngine {
    lexicon: Arc<Lexicon>,
    settings: ImeSettings,
}

impl ImeEngine {
    pub fn new() -> ImeResult<Self> {
        Self::with_settings(ImeSettings::default())
    }

    pub fn with_settings(settings: ImeSettings) -> ImeResult<Self> {
        Ok(Self {
            lexicon: Arc::new(Lexicon::load_embedded()?),
            settings,
        })
    }

    pub fn create_session(&self) -> InputSession {
        InputSession::new(self.lexicon.clone(), self.settings.clone())
    }

    pub fn candidates_for_raw(&self, raw_input: &str) -> Vec<Candidate> {
        let parser = PinyinParser;
        let parses = parser.parse(raw_input);
        self.lexicon.lookup(raw_input, &parses)
    }

    pub fn feed_text(&self, text: &str) -> ImeOutput {
        let mut session = self.create_session();
        let mut output = ImeOutput::idle(session.mode());
        for ch in text.chars() {
            output = session.feed_key(KeyEvent::from_char(ch));
        }
        output
    }
}
