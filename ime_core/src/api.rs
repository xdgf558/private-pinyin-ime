use std::path::Path;
use std::sync::Arc;

use crate::candidate::Candidate;
use crate::error::ImeResult;
use crate::imported_lexicon::{self, ImportedLexiconReport};
use crate::key_event::KeyEvent;
use crate::lexicon::Lexicon;
use crate::logger;
use crate::pinyin_parser::PinyinParser;
use crate::predictor::Predictor;
use crate::ranker::Ranker;
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

    pub fn from_settings_path(path: impl AsRef<Path>) -> ImeResult<Self> {
        Self::with_settings(ImeSettings::from_json_file_or_default(path))
    }

    pub fn with_settings(settings: ImeSettings) -> ImeResult<Self> {
        let user_lexicon = settings
            .user_lexicon_path
            .as_ref()
            .map(UserLexicon::open)
            .transpose()?
            .map(Arc::new);

        let lexicon = match settings.imported_lexicon_path.as_ref() {
            Some(path) if path.exists() => match Lexicon::load_embedded_with_imported(path) {
                Ok(lexicon) => lexicon,
                Err(error) => {
                    logger::emit_error(error);
                    Lexicon::load_embedded()?
                }
            },
            _ => Lexicon::load_embedded()?,
        };

        Ok(Self {
            lexicon: Arc::new(lexicon),
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

    pub fn settings(&self) -> &ImeSettings {
        &self.settings
    }

    pub fn clear_user_lexicon(&self) -> ImeResult<()> {
        if let Some(user_lexicon) = &self.user_lexicon {
            user_lexicon.clear()?;
        }
        Ok(())
    }

    pub fn export_user_lexicon(&self, path: impl AsRef<Path>) -> ImeResult<usize> {
        if let Some(user_lexicon) = &self.user_lexicon {
            user_lexicon.export_tsv(path)
        } else {
            UserLexicon::export_empty_tsv(path)
        }
    }

    pub fn import_rime_lexicon(
        &self,
        source_path: impl AsRef<Path>,
    ) -> ImeResult<ImportedLexiconReport> {
        let destination_path = self
            .settings
            .imported_lexicon_path
            .as_ref()
            .ok_or(crate::error::ImeError::ImportedLexiconNotConfigured)?;
        imported_lexicon::import_rime_file(source_path, destination_path)
    }

    pub fn clear_imported_lexicon(&self) -> ImeResult<()> {
        let destination_path = self
            .settings
            .imported_lexicon_path
            .as_ref()
            .ok_or(crate::error::ImeError::ImportedLexiconNotConfigured)?;
        imported_lexicon::clear_imported_file(destination_path)
    }

    pub fn candidates_for_raw(&self, raw_input: &str) -> Vec<Candidate> {
        let parser = PinyinParser;
        let parses = parser.parse(raw_input);
        let base_candidates =
            self.lexicon
                .lookup_with_context(raw_input, &parses, None, |left, right| {
                    Ranker::score_continuous_transition(
                        self.predictor.transition_frequency(left, right),
                        0,
                    )
                });
        let user_candidates = self
            .user_lexicon
            .as_ref()
            .map(
                |user_lexicon| match user_lexicon.lookup(raw_input, &parses) {
                    Ok(candidates) => candidates,
                    Err(error) => {
                        logger::emit_error(error);
                        Vec::new()
                    }
                },
            )
            .unwrap_or_default();
        crate::lexicon::merge_user_and_base_candidates(user_candidates, base_candidates)
    }

    pub fn candidates_for_nine_key(&self, digits: &str) -> Vec<Candidate> {
        let base_candidates =
            self.lexicon
                .lookup_nine_key_with_context(digits, None, |left, right| {
                    Ranker::score_continuous_transition(
                        self.predictor.transition_frequency(left, right),
                        0,
                    )
                });
        let user_candidates = self
            .user_lexicon
            .as_ref()
            .map(|user_lexicon| match user_lexicon.lookup_nine_key(digits) {
                Ok(candidates) => candidates,
                Err(error) => {
                    logger::emit_error(error);
                    Vec::new()
                }
            })
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
