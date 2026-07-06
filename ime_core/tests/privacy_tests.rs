use std::sync::{Arc, Mutex};

use ime_core::error::ImeError;
use ime_core::logger::{emit_error, format_log_event, set_log_sink, LogEvent};
use ime_core::privacy::{message_contains_forbidden_content, sanitized_error_code};

#[test]
fn error_display_uses_sanitized_code() {
    let error = ImeError::InvalidLexiconFormat;
    let message = error.to_string();

    assert_eq!(message, "INVALID_LEXICON_FORMAT");
    assert!(!message_contains_forbidden_content(
        &message,
        &["nihao", "你好"]
    ));
}

#[test]
fn logger_does_not_embed_user_input_in_error_events() {
    let message = format_log_event(&LogEvent::Error(ImeError::InvalidLexiconFrequency));

    assert_eq!(message, "error code=INVALID_LEXICON_FREQUENCY");
    assert!(!message_contains_forbidden_content(
        &message,
        &["nihao", "你好"]
    ));
}

#[test]
fn privacy_helper_returns_error_code_only() {
    assert_eq!(
        sanitized_error_code(&ImeError::MissingLexiconField),
        "MISSING_LEXICON_FIELD"
    );
}

#[test]
fn emitted_error_logs_are_sanitized() {
    let messages = Arc::new(Mutex::new(Vec::<String>::new()));
    let captured_messages = messages.clone();

    set_log_sink(Some(Arc::new(move |message| {
        captured_messages
            .lock()
            .expect("capture log message")
            .push(message);
    })));
    emit_error(ImeError::UserLexiconDatabase);
    set_log_sink(None);

    let messages = messages.lock().expect("read captured messages");
    assert_eq!(messages.as_slice(), ["error code=USER_LEXICON_DATABASE"]);
    assert!(!message_contains_forbidden_content(
        &messages[0],
        &["nihao", "你好"]
    ));
}
