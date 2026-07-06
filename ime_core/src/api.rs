use std::sync::Arc;

use crate::candidate::Candidate;
use crate::error::ImeResult;
use crate::key_event::KeyEvent;
use crate::lexicon::Lexicon;
use crate::pinyin_parser::PinyinParser;
use crate::predictor::Predictor;
use crate::session::InputSession;
use crate::settings::{ImeMode, ImeSettings};
use crate::user_lexicon::UserLexicon;

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
    predictor: Arc<Predictor>,
    user_lexicon: Option<Arc<UserLexicon>>,
    settings: ImeSettings,
}

impl ImeEngine {
    pub fn new() -> ImeResult<Self> {
        Self::with_settings(ImeSettings::default())
    }

    pub fn with_settings(settings: ImeSettings) -> ImeResult<Self> {
        let user_lexicon = settings
            .user_lexicon_path
            .as_ref()
            .map(UserLexicon::open)
            .transpose()?
            .map(Arc::new);

        Ok(Self {
            lexicon: Arc::new(Lexicon::load_embedded()?),
            predictor: Arc::new(Predictor::load_embedded()?),
            user_lexicon,
            settings,
        })
    }

    pub fn create_session(&self) -> InputSession {
        InputSession::new(
            self.lexicon.clone(),
            self.predictor.clone(),
            self.user_lexicon.clone(),
            self.settings.clone(),
        )
    }

    pub fn candidates_for_raw(&self, raw_input: &str) -> Vec<Candidate> {
        let parser = PinyinParser;
        let parses = parser.parse(raw_input);
        let base_candidates = self.lexicon.lookup(raw_input, &parses);
        let user_candidates = self
            .user_lexicon
            .as_ref()
            .map(|user_lexicon| user_lexicon.lookup(raw_input, &parses).unwrap_or_default())
            .unwrap_or_default();
        crate::lexicon::merge_user_and_base_candidates(user_candidates, base_candidates)
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
