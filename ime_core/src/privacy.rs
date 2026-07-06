use crate::error::ImeError;

pub fn sanitized_error_code(error: &ImeError) -> &'static str {
    error.code()
}

pub fn message_contains_forbidden_content(message: &str, forbidden_content: &[&str]) -> bool {
    forbidden_content
        .iter()
        .filter(|content| !content.is_empty())
        .any(|content| message.contains(content))
}
