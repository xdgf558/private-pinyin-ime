use ime_core::error::ImeError;
use ime_core::logger::{format_log_event, LogEvent};
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
