use std::sync::Arc;

use crate::api::ImeOutput;
use crate::candidate::Candidate;
use crate::key_event::{KeyCode, KeyEvent};
use crate::lexicon::{
    merge_user_and_base_candidates, ContinuousDecodeCache, Lexicon, MAX_LOOKUP_CANDIDATES,
};
use crate::logger;
use crate::pinyin_parser::PinyinParser;
use crate::predictor::{merge_prediction_candidates, Predictor};
use crate::ranker::Ranker;
use crate::settings::{ImeMode, ImeSettings, ToggleKey};
use crate::user_lexicon::{UserLexicon, UserTransitionSnapshot};

pub const MAX_RAW_INPUT_CHARS: usize = 64;
pub const MAX_CONTEXT_TOKENS: usize = 8;

#[derive(Debug, Clone)]
pub struct InputSession {
    mode: ImeMode,
    pub raw_input: String,
    pub nine_key_input: String,
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
    user_transitions: UserTransitionSnapshot,
    continuous_decode_cache: ContinuousDecodeCache,
}

impl InputSession {
    pub fn new(
        lexicon: Arc<Lexicon>,
        predictor: Arc<Predictor>,
        user_lexicon: Option<Arc<UserLexicon>>,
        settings_snapshot: ImeSettings,
    ) -> Self {
        let privacy_mode = settings_snapshot.strict_privacy_mode;
        let user_transitions = user_lexicon
            .as_ref()
            .map(|lexicon| match lexicon.transition_snapshot() {
                Ok(snapshot) => snapshot,
                Err(error) => {
                    logger::emit_error(error);
                    UserTransitionSnapshot::new()
                }
            })
            .unwrap_or_default();
        Self {
            mode: settings_snapshot.default_mode,
            raw_input: String::new(),
            nine_key_input: String::new(),
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
            user_transitions,
            continuous_decode_cache: ContinuousDecodeCache::default(),
        }
    }

    pub fn mode(&self) -> ImeMode {
        self.mode
    }

    pub fn current_page_candidates_snapshot(&self) -> Vec<Candidate> {
        self.current_page_candidates()
    }

    pub fn set_candidate_page_size(&mut self, page_size: usize) -> bool {
        if !(1..=MAX_LOOKUP_CANDIDATES).contains(&page_size) {
            return false;
        }

        self.settings_snapshot.candidate_page_size = page_size;
        self.candidate_page = 0;
        true
    }

    pub fn reorder_current_candidate_page(&mut self, order: &[usize]) -> bool {
        let start = self.page_start().min(self.candidates.len());
        let end = (start + self.page_size()).min(self.candidates.len());
        let page_len = end.saturating_sub(start);
        if order.len() != page_len {
            return false;
        }

        let mut seen = vec![false; page_len];
        for &index in order {
            if index >= page_len || seen[index] {
                return false;
            }
            seen[index] = true;
        }

        let original = self.candidates[start..end].to_vec();
        for (target_index, &source_index) in order.iter().enumerate() {
            self.candidates[start + target_index] = original[source_index].clone();
        }
        true
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
                if !self.nine_key_input.is_empty() {
                    self.clear_composition();
                }
                if self.raw_input.chars().count() >= MAX_RAW_INPUT_CHARS {
                    return self.current_output(false, false, String::new());
                }

                self.raw_input.push(ch.to_ascii_lowercase());
                self.refresh_composition()
            }
            KeyCode::Apostrophe => {
                if !self.nine_key_input.is_empty() {
                    self.current_output(false, false, String::new())
                } else if self.raw_input.is_empty() {
                    self.commit_text("'")
                } else if self.raw_input.chars().count() >= MAX_RAW_INPUT_CHARS {
                    self.current_output(false, false, String::new())
                } else {
                    self.raw_input.push('\'');
                    self.refresh_composition()
                }
            }
            KeyCode::Space => {
                if !self.has_composition_input() {
                    self.commit_text(" ")
                } else if self.candidates.is_empty() {
                    self.commit_raw_input()
                } else {
                    self.commit_candidate(0)
                }
            }
            KeyCode::Digit(index @ 1..=9) => {
                if !self.has_composition_input() {
                    if self.candidates.is_empty() {
                        ImeOutput::idle(self.mode)
                    } else {
                        self.commit_candidate(usize::from(index - 1))
                    }
                } else {
                    self.commit_candidate(usize::from(index - 1))
                }
            }
            KeyCode::NineKeyDigit(digit @ 2..=9) => {
                if !self.raw_input.is_empty() {
                    self.clear_composition();
                }
                if self.nine_key_input.len() >= MAX_RAW_INPUT_CHARS {
                    return self.current_output(false, false, String::new());
                }
                self.nine_key_input.push(char::from(b'0' + digit));
                self.refresh_nine_key_composition()
            }
            KeyCode::Enter => {
                if !self.has_composition_input() {
                    ImeOutput::idle(self.mode)
                } else {
                    self.commit_raw_input()
                }
            }
            KeyCode::Escape => self.cancel_composition(),
            KeyCode::Backspace => {
                if self.nine_key_input.is_empty() {
                    self.raw_input.pop();
                    self.refresh_composition()
                } else {
                    self.nine_key_input.pop();
                    self.refresh_nine_key_composition()
                }
            }
            KeyCode::PageDown | KeyCode::ArrowDown => self.turn_candidate_page(1),
            KeyCode::PageUp | KeyCode::ArrowUp => self.turn_candidate_page(-1),
            KeyCode::Comma => self.commit_punctuation("，"),
            KeyCode::Period => self.commit_punctuation("。"),
            KeyCode::Minus => self.commit_punctuation("－"),
            KeyCode::Equal => self.commit_punctuation("＝"),
            KeyCode::Semicolon => self.commit_punctuation("；"),
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
        self.append_candidate_context(&candidate);
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
        let commit_text = self.composition_input().to_owned();
        self.clear_composition();
        self.committed_output(commit_text)
    }

    fn commit_punctuation(&mut self, punctuation: &str) -> ImeOutput {
        if !self.has_composition_input() {
            self.commit_text(punctuation)
        } else if let Some(actual_index) = self.actual_candidate_index(0) {
            if let Some(candidate) = self.candidates.get(actual_index).cloned() {
                self.learn_candidate(&candidate);
                self.append_candidate_context(&candidate);
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
        if !self.has_composition_input()
            && self.mode == ImeMode::Chinese
            && self.settings_snapshot.enable_prediction
        {
            let base_candidates = self.predictor.predict_next(&self.context_tokens);
            let Some(last_token) = self.context_tokens.last() else {
                return base_candidates;
            };
            let mut user_candidates = Vec::new();
            if let Some(user_lexicon) = &self.user_lexicon {
                if self.context_tokens.len() >= 2 {
                    let first_index = self.context_tokens.len() - 2;
                    match user_lexicon
                        .predict_trigram(&self.context_tokens[first_index], last_token)
                    {
                        Ok(candidates) => user_candidates.extend(candidates),
                        Err(error) => logger::emit_error(error),
                    }
                }
                match user_lexicon.predict_short_phrases(last_token) {
                    Ok(candidates) => user_candidates.extend(candidates),
                    Err(error) => logger::emit_error(error),
                }
                match user_lexicon.predict_next(last_token) {
                    Ok(candidates) => user_candidates.extend(candidates),
                    Err(error) => logger::emit_error(error),
                }
            }
            merge_prediction_candidates(user_candidates, base_candidates)
        } else {
            Vec::new()
        }
    }

    fn learn_short_phrase_prediction(&self, candidate: &Candidate, user_lexicon: &UserLexicon) {
        if self.context_tokens.len() < 2 {
            return;
        }

        let left_index = self.context_tokens.len() - 2;
        let left = &self.context_tokens[left_index];
        let middle = &self.context_tokens[left_index + 1];
        let phrase = format!("{middle}{}", candidate.text);
        if let Err(error) = user_lexicon.record_short_phrase_prediction(left, &phrase, 2) {
            logger::emit_error(error);
        }
    }

    fn learn_trigrams(
        &self,
        segments: &[crate::candidate::CandidateSegment],
        user_lexicon: &UserLexicon,
    ) {
        let previous = self
            .context_tokens
            .iter()
            .rev()
            .take(2)
            .rev()
            .cloned()
            .collect::<Vec<_>>();
        let previous_len = previous.len();
        let mut tokens = previous
            .into_iter()
            .map(|text| crate::candidate::CandidateSegment {
                text,
                pinyin: String::new(),
            })
            .collect::<Vec<_>>();
        tokens.extend_from_slice(segments);

        for window_start in 0..tokens.len().saturating_sub(2) {
            let next_index = window_start + 2;
            if next_index < previous_len {
                continue;
            }
            let first = &tokens[window_start];
            let second = &tokens[window_start + 1];
            let next = &tokens[next_index];
            if let Err(error) =
                user_lexicon.record_trigram(&first.text, &second.text, &next.text, &next.pinyin)
            {
                logger::emit_error(error);
            }
        }
    }

    fn append_candidate_context(&mut self, candidate: &Candidate) {
        self.context_tokens.extend(
            candidate_segments(candidate)
                .into_iter()
                .map(|segment| segment.text),
        );
        if self.context_tokens.len() > MAX_CONTEXT_TOKENS {
            let excess = self.context_tokens.len() - MAX_CONTEXT_TOKENS;
            self.context_tokens.drain(..excess);
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
        let previous_context = self.context_tokens.last().map(String::as_str);
        let base_candidates = self.lexicon.lookup_with_context_cached(
            &self.raw_input,
            &parses,
            previous_context,
            |left, right| {
                Ranker::score_continuous_transition_weight(
                    self.predictor.transition_frequency(left, right),
                    user_transition_frequency(&self.user_transitions, left, right),
                )
            },
            &mut self.continuous_decode_cache,
        );
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

    fn refresh_nine_key_composition(&mut self) -> ImeOutput {
        if self.nine_key_input.is_empty() {
            self.clear_composition();
            return self.current_output(true, false, String::new());
        }

        self.parsed_syllables.clear();
        let previous_context = self.context_tokens.last().map(String::as_str);
        let base_candidates = self.lexicon.lookup_nine_key_with_context(
            &self.nine_key_input,
            previous_context,
            |left, right| {
                Ranker::score_continuous_transition_weight(
                    self.predictor.transition_frequency(left, right),
                    user_transition_frequency(&self.user_transitions, left, right),
                )
            },
        );
        let user_candidates = self
            .user_lexicon
            .as_ref()
            .map(
                |user_lexicon| match user_lexicon.lookup_nine_key(&self.nine_key_input) {
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
        self.preedit_text = self.nine_key_input.clone();
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
        self.nine_key_input.clear();
        self.parsed_syllables.clear();
        self.preedit_text.clear();
        self.candidates.clear();
        self.candidate_page = 0;
        self.continuous_decode_cache.clear();
    }

    fn has_active_input(&self) -> bool {
        self.has_composition_input() || !self.candidates.is_empty()
    }

    fn has_composition_input(&self) -> bool {
        !self.raw_input.is_empty() || !self.nine_key_input.is_empty()
    }

    fn composition_input(&self) -> &str {
        if self.nine_key_input.is_empty() {
            &self.raw_input
        } else {
            &self.nine_key_input
        }
    }

    fn commit_raw_input_with_suffix(&mut self, suffix: &str) -> ImeOutput {
        let commit_text = format!("{}{}", self.composition_input(), suffix);
        self.clear_composition();
        self.committed_output(commit_text)
    }

    fn turn_candidate_page(&mut self, delta: isize) -> ImeOutput {
        if self.candidates.is_empty() {
            return if !self.has_composition_input() {
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

    fn learn_candidate(&mut self, candidate: &Candidate) {
        if self.privacy_mode || !self.settings_snapshot.enable_user_learning {
            return;
        }

        let Some(user_lexicon) = self.user_lexicon.clone() else {
            return;
        };
        if let Err(error) = user_lexicon.record_selection(&candidate.text, &candidate.pinyin) {
            logger::emit_error(error);
        }
        let segments = candidate_segments(candidate);
        let previous = self.context_tokens.last().cloned();
        if let (Some(previous), Some(first)) = (previous, segments.first()) {
            self.record_learned_transition(&previous, first);
        }
        for pair in segments.windows(2) {
            self.record_learned_transition(&pair[0].text, &pair[1]);
        }
        self.learn_trigrams(&segments, &user_lexicon);
        self.learn_short_phrase_prediction(candidate, &user_lexicon);
    }

    fn record_learned_transition(
        &mut self,
        left: &str,
        right: &crate::candidate::CandidateSegment,
    ) {
        let Some(user_lexicon) = self.user_lexicon.clone() else {
            return;
        };
        match user_lexicon.record_transition(left, &right.text, &right.pinyin) {
            Ok(()) => {
                let frequency = self
                    .user_transitions
                    .entry(left.to_owned())
                    .or_default()
                    .entry(right.text.clone())
                    .or_default();
                *frequency += 1.0;
            }
            Err(error) => logger::emit_error(error),
        }
    }
}

fn candidate_segments(candidate: &Candidate) -> Vec<crate::candidate::CandidateSegment> {
    if candidate.segments.is_empty() {
        vec![crate::candidate::CandidateSegment {
            text: candidate.text.clone(),
            pinyin: candidate.pinyin.clone(),
        }]
    } else {
        candidate.segments.clone()
    }
}

fn user_transition_frequency(transitions: &UserTransitionSnapshot, left: &str, right: &str) -> f64 {
    transitions
        .get(left)
        .and_then(|right_entries| right_entries.get(right))
        .copied()
        .unwrap_or_default()
}

fn has_passthrough_modifier(event: &KeyEvent) -> bool {
    event.modifiers.ctrl || event.modifiers.alt || event.modifiers.meta
}
