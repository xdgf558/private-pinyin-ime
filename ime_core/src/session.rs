use std::sync::Arc;

use crate::api::ImeOutput;
use crate::candidate::Candidate;
use crate::key_event::{KeyCode, KeyEvent};
use crate::lexicon::{merge_user_and_base_candidates, Lexicon};
use crate::logger;
use crate::pinyin_parser::PinyinParser;
use crate::predictor::{merge_prediction_candidates, Predictor};
use crate::settings::{ImeMode, ImeSettings, ToggleKey};
use crate::user_lexicon::UserLexicon;

pub const MAX_RAW_INPUT_CHARS: usize = 64;

#[derive(Debug, Clone)]
pub struct InputSession {
    mode: ImeMode,
    pub raw_input: String,
    pub parsed_syllables: Vec<String>,
    pub preedit_text: String,
    pub candidates: Vec<Candidate>,
    pub candidate_page: usize,
    pub context_tokens: Vec<String>,
    pub settings_snapshot: ImeSettings,
    pub privacy_mode: bool,
    lexicon: Arc<Lexicon>,
    predictor: Arc<Predictor>,
    user_lexicon: Option<Arc<UserLexicon>>,
}

impl InputSession {
    pub fn new(
        lexicon: Arc<Lexicon>,
        predictor: Arc<Predictor>,
        user_lexicon: Option<Arc<UserLexicon>>,
        settings_snapshot: ImeSettings,
    ) -> Self {
        let privacy_mode = settings_snapshot.strict_privacy_mode;
        Self {
            mode: settings_snapshot.default_mode,
            raw_input: String::new(),
            parsed_syllables: Vec::new(),
            preedit_text: String::new(),
            candidates: Vec::new(),
            candidate_page: 0,
            context_tokens: Vec::new(),
            settings_snapshot,
            privacy_mode,
            lexicon,
            predictor,
            user_lexicon,
        }
    }

    pub fn mode(&self) -> ImeMode {
        self.mode
    }

    pub fn feed_key(&mut self, event: KeyEvent) -> ImeOutput {
        if self.is_toggle_event(&event) {
            return self.toggle_mode();
        }

        if has_passthrough_modifier(&event) {
            return ImeOutput::idle(self.mode);
        }

        if self.mode == ImeMode::English {
            return self.feed_english_key(event);
        }

        match event.key_code {
            KeyCode::Character(ch) if ch.is_ascii_alphabetic() => {
                if self.raw_input.chars().count() >= MAX_RAW_INPUT_CHARS {
                    return self.current_output(false, false, String::new());
                }

                self.raw_input.push(ch.to_ascii_lowercase());
                self.refresh_composition()
            }
            KeyCode::Apostrophe => {
                if self.raw_input.is_empty() {
                    self.commit_text("'")
                } else if self.raw_input.chars().count() >= MAX_RAW_INPUT_CHARS {
                    self.current_output(false, false, String::new())
                } else {
                    self.raw_input.push('\'');
                    self.refresh_composition()
                }
            }
            KeyCode::Space => {
                if self.raw_input.is_empty() {
                    self.commit_text(" ")
                } else if self.candidates.is_empty() {
                    self.commit_raw_input()
                } else {
                    self.commit_candidate(0)
                }
            }
            KeyCode::Digit(index @ 1..=9) => {
                if self.raw_input.is_empty() {
                    if self.candidates.is_empty() {
                        ImeOutput::idle(self.mode)
                    } else {
                        self.commit_candidate(usize::from(index - 1))
                    }
                } else {
                    self.commit_candidate(usize::from(index - 1))
                }
            }
            KeyCode::Enter => {
                if self.raw_input.is_empty() {
                    ImeOutput::idle(self.mode)
                } else {
                    self.commit_raw_input()
                }
            }
            KeyCode::Escape => self.cancel_composition(),
            KeyCode::Backspace => {
                self.raw_input.pop();
                self.refresh_composition()
            }
            KeyCode::PageDown | KeyCode::ArrowDown => self.turn_candidate_page(1),
            KeyCode::PageUp | KeyCode::ArrowUp => self.turn_candidate_page(-1),
            KeyCode::Comma => self.commit_punctuation(","),
            KeyCode::Period => self.commit_punctuation("."),
            KeyCode::Minus => self.commit_punctuation("-"),
            KeyCode::Equal => self.commit_punctuation("="),
            KeyCode::Semicolon => self.commit_punctuation(";"),
            _ => {
                if self.has_active_input() {
                    self.current_output(false, false, String::new())
                } else {
                    ImeOutput::idle(self.mode)
                }
            }
        }
    }

    pub fn commit_candidate(&mut self, index: usize) -> ImeOutput {
        let Some(actual_index) = self.actual_candidate_index(index) else {
            return self.current_output(false, false, String::new());
        };
        let Some(candidate) = self.candidates.get(actual_index).cloned() else {
            return self.current_output(false, false, String::new());
        };

        self.learn_candidate(&candidate);
        self.context_tokens.push(candidate.text.clone());
        self.clear_composition();
        self.candidates = self.predict_next();
        let candidates = self.current_page_candidates();

        ImeOutput {
            preedit: String::new(),
            commit_text: candidate.text,
            mode: self.mode,
            should_update_preedit: true,
            should_commit: true,
            should_show_candidates: !candidates.is_empty(),
            candidates,
        }
    }

    pub fn commit_raw_input(&mut self) -> ImeOutput {
        let commit_text = self.raw_input.clone();
        self.clear_composition();
        self.committed_output(commit_text)
    }

    fn commit_punctuation(&mut self, punctuation: &str) -> ImeOutput {
        if self.raw_input.is_empty() {
            self.commit_text(punctuation)
        } else if let Some(actual_index) = self.actual_candidate_index(0) {
            if let Some(candidate) = self.candidates.get(actual_index).cloned() {
                self.learn_candidate(&candidate);
                self.context_tokens.push(candidate.text.clone());
                let commit_text = format!("{}{}", candidate.text, punctuation);
                self.clear_composition();
                self.committed_output(commit_text)
            } else {
                self.commit_raw_input_with_suffix(punctuation)
            }
        } else {
            self.commit_raw_input_with_suffix(punctuation)
        }
    }

    fn commit_text(&mut self, text: &str) -> ImeOutput {
        self.clear_composition();
        self.committed_output(text.to_owned())
    }

    fn committed_output(&self, commit_text: String) -> ImeOutput {
        ImeOutput {
            preedit: String::new(),
            commit_text,
            mode: self.mode,
            should_update_preedit: true,
            should_commit: true,
            should_show_candidates: false,
            candidates: Vec::new(),
        }
    }

    pub fn cancel_composition(&mut self) -> ImeOutput {
        self.clear_composition();
        self.current_output(true, false, String::new())
    }

    pub fn toggle_mode(&mut self) -> ImeOutput {
        self.clear_composition();
        self.mode = match self.mode {
            ImeMode::Chinese => ImeMode::English,
            ImeMode::English => ImeMode::Chinese,
        };
        self.current_output(true, false, String::new())
    }

    pub fn reset(&mut self) -> ImeOutput {
        self.clear_composition();
        self.context_tokens.clear();
        self.current_output(true, false, String::new())
    }

    pub fn predict_next(&self) -> Vec<Candidate> {
        if self.raw_input.is_empty()
            && self.mode == ImeMode::Chinese
            && self.settings_snapshot.enable_prediction
        {
            let base_candidates = self.predictor.predict_next(&self.context_tokens);
            let Some(last_token) = self.context_tokens.last() else {
                return base_candidates;
            };
            let user_candidates = self
                .user_lexicon
                .as_ref()
                .map(|user_lexicon| match user_lexicon.predict_next(last_token) {
                    Ok(candidates) => candidates,
                    Err(error) => {
                        logger::emit_error(error);
                        Vec::new()
                    }
                })
                .unwrap_or_default();
            merge_prediction_candidates(user_candidates, base_candidates)
        } else {
            Vec::new()
        }
    }

    fn refresh_composition(&mut self) -> ImeOutput {
        if self.raw_input.is_empty() {
            self.clear_composition();
            return self.current_output(true, false, String::new());
        }

        let parser = PinyinParser;
        let parses = parser.parse(&self.raw_input);
        self.parsed_syllables = parses
            .first()
            .map(|parse| parse.syllable_texts())
            .unwrap_or_default();
        let base_candidates = self.lexicon.lookup(&self.raw_input, &parses);
        let user_candidates = self
            .user_lexicon
            .as_ref()
            .map(
                |user_lexicon| match user_lexicon.lookup(&self.raw_input, &parses) {
                    Ok(candidates) => candidates,
                    Err(error) => {
                        logger::emit_error(error);
                        Vec::new()
                    }
                },
            )
            .unwrap_or_default();
        self.candidates = merge_user_and_base_candidates(user_candidates, base_candidates);
        self.candidate_page = 0;
        self.preedit_text = self.raw_input.clone();
        self.current_output(true, false, String::new())
    }

    fn feed_english_key(&mut self, event: KeyEvent) -> ImeOutput {
        let commit_text = if event.text.is_empty() {
            match event.key_code {
                KeyCode::Space => " ".to_owned(),
                KeyCode::Enter => "\n".to_owned(),
                _ => String::new(),
            }
        } else {
            event.text
        };

        ImeOutput {
            preedit: String::new(),
            commit_text,
            mode: self.mode,
            should_update_preedit: false,
            should_commit: true,
            should_show_candidates: false,
            candidates: Vec::new(),
        }
    }

    fn current_output(
        &self,
        should_update_preedit: bool,
        should_commit: bool,
        commit_text: String,
    ) -> ImeOutput {
        let candidates = self.current_page_candidates();
        ImeOutput {
            preedit: self.preedit_text.clone(),
            commit_text,
            mode: self.mode,
            should_update_preedit,
            should_commit,
            should_show_candidates: !candidates.is_empty(),
            candidates,
        }
    }

    fn is_toggle_event(&self, event: &KeyEvent) -> bool {
        matches!(
            (&self.settings_snapshot.toggle_key, event.key_code),
            (ToggleKey::Shift, KeyCode::Shift)
                | (ToggleKey::CtrlSpace, KeyCode::CtrlSpace)
                | (ToggleKey::CapsLock, KeyCode::CapsLock)
        )
    }

    fn clear_composition(&mut self) {
        self.raw_input.clear();
        self.parsed_syllables.clear();
        self.preedit_text.clear();
        self.candidates.clear();
        self.candidate_page = 0;
    }

    fn has_active_input(&self) -> bool {
        !self.raw_input.is_empty() || !self.candidates.is_empty()
    }

    fn commit_raw_input_with_suffix(&mut self, suffix: &str) -> ImeOutput {
        let commit_text = format!("{}{}", self.raw_input, suffix);
        self.clear_composition();
        self.committed_output(commit_text)
    }

    fn turn_candidate_page(&mut self, delta: isize) -> ImeOutput {
        if self.candidates.is_empty() {
            return if self.raw_input.is_empty() {
                ImeOutput::idle(self.mode)
            } else {
                self.current_output(false, false, String::new())
            };
        }

        let page_count = self.page_count();
        if delta > 0 {
            self.candidate_page = (self.candidate_page + 1).min(page_count.saturating_sub(1));
        } else if delta < 0 {
            self.candidate_page = self.candidate_page.saturating_sub(1);
        }
        self.current_output(false, false, String::new())
    }

    fn page_size(&self) -> usize {
        self.settings_snapshot.candidate_page_size.max(1)
    }

    fn page_count(&self) -> usize {
        self.candidates.len().div_ceil(self.page_size()).max(1)
    }

    fn page_start(&self) -> usize {
        self.candidate_page * self.page_size()
    }

    fn actual_candidate_index(&self, page_index: usize) -> Option<usize> {
        if page_index >= self.page_size() {
            return None;
        }

        let actual_index = self.page_start().checked_add(page_index)?;
        (actual_index < self.candidates.len()).then_some(actual_index)
    }

    fn current_page_candidates(&self) -> Vec<Candidate> {
        let page_size = self.page_size();
        let start = self.page_start().min(self.candidates.len());
        let end = (start + page_size).min(self.candidates.len());
        self.candidates[start..end].to_vec()
    }

    fn learn_candidate(&self, candidate: &Candidate) {
        if self.privacy_mode || !self.settings_snapshot.enable_user_learning {
            return;
        }

        if let Some(user_lexicon) = &self.user_lexicon {
            if let Err(error) = user_lexicon.record_selection(&candidate.text, &candidate.pinyin) {
                logger::emit_error(error);
            }
            if let Some(previous) = self.context_tokens.last() {
                if let Err(error) =
                    user_lexicon.record_transition(previous, &candidate.text, &candidate.pinyin)
                {
                    logger::emit_error(error);
                }
            }
        }
    }
}

fn has_passthrough_modifier(event: &KeyEvent) -> bool {
    event.modifiers.ctrl || event.modifiers.alt || event.modifiers.meta
}
