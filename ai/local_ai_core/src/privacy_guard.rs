use crate::{AiBudget, AiError, AiErrorCode, AiPrivacyMode, AiRawInputKind, AiRequest};

pub const MAX_RAW_PINYIN_CHARS: usize = 64;
pub const MAX_COMPOSITION_TEXT_UNITS: usize = 600;
pub const MAX_BASE_CANDIDATES: usize = 64;
pub const MAX_CANDIDATE_TEXT_UNITS: usize = 192;
pub const MAX_CANDIDATE_PINYIN_CHARS: usize = 256;
pub const MAX_RECENT_TOKENS: usize = 8;
pub const MAX_RECENT_TOKEN_UNITS: usize = 96;
pub const MAX_LOCALE_CHARS: usize = 32;
pub const MAX_TOTAL_CONTEXT_UNITS: usize = 4_096;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AiModelLicenseState {
    NotRequired,
    Approved,
    NotApproved,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AiFeaturePolicy {
    enabled: bool,
    allow_in_strict_privacy: bool,
    model_license: AiModelLicenseState,
}

impl AiFeaturePolicy {
    pub const fn new(
        enabled: bool,
        allow_in_strict_privacy: bool,
        model_license: AiModelLicenseState,
    ) -> Self {
        Self {
            enabled,
            allow_in_strict_privacy,
            model_license,
        }
    }

    pub const fn local_rules_enabled(allow_in_strict_privacy: bool) -> Self {
        Self::new(
            true,
            allow_in_strict_privacy,
            AiModelLicenseState::NotRequired,
        )
    }

    pub const fn approved_model_enabled(allow_in_strict_privacy: bool) -> Self {
        Self::new(true, allow_in_strict_privacy, AiModelLicenseState::Approved)
    }

    pub const fn disabled() -> Self {
        Self::new(false, false, AiModelLicenseState::NotRequired)
    }

    pub const fn enabled(self) -> bool {
        self.enabled
    }

    pub const fn allow_in_strict_privacy(self) -> bool {
        self.allow_in_strict_privacy
    }

    pub const fn model_license(self) -> AiModelLicenseState {
        self.model_license
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct PrivacyGuard;

impl PrivacyGuard {
    pub(crate) fn minimize_recent_tokens(&self, tokens: Vec<String>) -> Vec<String> {
        let mut tokens = tokens
            .into_iter()
            .filter(|token| !token.trim().is_empty())
            .collect::<Vec<_>>();
        if tokens.len() > MAX_RECENT_TOKENS {
            tokens.drain(..tokens.len() - MAX_RECENT_TOKENS);
        }
        tokens
    }

    pub(crate) fn validate(
        &self,
        request: &AiRequest,
        policy: AiFeaturePolicy,
    ) -> Result<(), AiError> {
        if !policy.enabled()
            || (request.privacy_mode() == AiPrivacyMode::Strict
                && !policy.allow_in_strict_privacy())
        {
            return Err(AiError::new(AiErrorCode::Disabled));
        }
        if policy.model_license() == AiModelLicenseState::NotApproved {
            return Err(AiError::new(AiErrorCode::ModelLicenseNotApproved));
        }
        if request.secure_input() {
            return Err(privacy_rejection());
        }
        if !request.hardware_tier().supports(request.feature()) {
            return Err(AiError::new(AiErrorCode::HardwareTooLow));
        }
        validate_budget(request)?;
        if request.deadline().is_expired() {
            return Err(AiError::new(AiErrorCode::Timeout));
        }
        if !request.has_consistent_candidate_identity() {
            return Err(AiError::new(AiErrorCode::IdentityMismatch));
        }
        if request.feature().requires_explicit_user_action() && !request.user_action_required() {
            return Err(privacy_rejection());
        }
        if !has_valid_sizes(request) || contains_sensitive_input(request) {
            return Err(privacy_rejection());
        }
        Ok(())
    }
}

fn validate_budget(request: &AiRequest) -> Result<(), AiError> {
    let budget = request.budget();
    let approved = AiBudget::for_feature(request.feature());
    if !budget.is_valid()
        || budget.max_elapsed() > approved.max_elapsed()
        || budget.max_candidates() > approved.max_candidates()
        || budget.max_suggestions() > approved.max_suggestions()
    {
        return Err(AiError::new(AiErrorCode::InvalidBudget));
    }
    Ok(())
}

fn has_valid_sizes(request: &AiRequest) -> bool {
    let locale = request.locale();
    if locale.is_empty()
        || locale.chars().count() > MAX_LOCALE_CHARS
        || !locale
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || character == '-')
    {
        return false;
    }

    if request
        .raw_pinyin()
        .is_some_and(|value| value.chars().count() > MAX_RAW_PINYIN_CHARS)
        || request
            .composition_text()
            .is_some_and(|value| text_units(value) > MAX_COMPOSITION_TEXT_UNITS)
        || request.base_candidates().len() > MAX_BASE_CANDIDATES
        || request.base_candidates().len() > request.budget().max_candidates()
        || request.recent_tokens().len() > MAX_RECENT_TOKENS
    {
        return false;
    }

    let mut total_units = request.raw_pinyin().map(text_units).unwrap_or_default();
    total_units = total_units.saturating_add(
        request
            .composition_text()
            .map(text_units)
            .unwrap_or_default(),
    );

    for candidate in request.base_candidates() {
        if text_units(candidate.text()) > MAX_CANDIDATE_TEXT_UNITS
            || candidate
                .pinyin()
                .is_some_and(|value| value.chars().count() > MAX_CANDIDATE_PINYIN_CHARS)
        {
            return false;
        }
        total_units = total_units.saturating_add(text_units(candidate.text()));
        total_units =
            total_units.saturating_add(candidate.pinyin().map(text_units).unwrap_or_default());
    }

    for token in request.recent_tokens() {
        let units = text_units(token);
        if units > MAX_RECENT_TOKEN_UNITS {
            return false;
        }
        total_units = total_units.saturating_add(units);
    }

    total_units <= MAX_TOTAL_CONTEXT_UNITS
}

fn contains_sensitive_input(request: &AiRequest) -> bool {
    if request.raw_pinyin().is_some_and(|value| {
        contains_secret_value(value)
            || (request.raw_input_kind() == AiRawInputKind::FullPinyin
                && (is_plain_one_time_code(value) || contains_sensitive_value(value)))
    }) {
        return true;
    }
    if request
        .composition_text()
        .is_some_and(contains_sensitive_context_value)
    {
        return true;
    }
    if request
        .recent_tokens()
        .iter()
        .any(|token| contains_sensitive_context_value(token))
    {
        return true;
    }
    request.base_candidates().iter().any(|candidate| {
        contains_sensitive_context_value(candidate.text())
            || candidate
                .pinyin()
                .is_some_and(contains_sensitive_context_value)
    })
}

fn contains_sensitive_context_value(value: &str) -> bool {
    is_plain_one_time_code(value) || contains_sensitive_value(value)
}

fn contains_sensitive_value(value: &str) -> bool {
    contains_secret_value(value)
        || contains_labeled_one_time_code(value)
        || contains_chinese_identity_number(value)
        || contains_phone_number(value)
        || contains_payment_card(value)
}

fn contains_secret_value(value: &str) -> bool {
    let compact = value
        .to_ascii_lowercase()
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect::<String>();
    const MARKERS: [&str; 22] = [
        "password=",
        "password:",
        "passwd=",
        "passwd:",
        "pwd=",
        "pwd:",
        "pin=",
        "pin:",
        "密码=",
        "密码:",
        "密碼=",
        "密碼:",
        "api_key=",
        "api_key:",
        "api-key=",
        "api-key:",
        "apikey=",
        "apikey:",
        "token=",
        "token:",
        "secret=",
        "secret:",
    ];
    MARKERS.iter().any(|marker| compact.contains(marker))
        || compact.contains("authorization:bearer")
}

fn contains_labeled_one_time_code(value: &str) -> bool {
    let lowercase = value.to_ascii_lowercase();
    const LABELS: [&str; 7] = [
        "验证码",
        "驗證碼",
        "动态码",
        "動態碼",
        "otp",
        "verificationcode",
        "one-timecode",
    ];
    let compact = lowercase
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect::<String>();
    LABELS.iter().any(|label| compact.contains(label)) && has_ascii_digit_run(value, 4, 8)
}

fn is_plain_one_time_code(value: &str) -> bool {
    let trimmed = value.trim();
    let digit_count = trimmed
        .chars()
        .filter(|character| character.is_ascii_digit())
        .count();
    (4..=8).contains(&digit_count)
        && trimmed
            .chars()
            .all(|character| character.is_ascii_digit() || character.is_whitespace())
}

fn contains_chinese_identity_number(value: &str) -> bool {
    value
        .split(|character: char| !character.is_ascii_alphanumeric())
        .any(|part| {
            (part.len() == 15 && part.bytes().all(|byte| byte.is_ascii_digit()))
                || (part.len() == 18
                    && part.as_bytes()[..17]
                        .iter()
                        .all(|byte| byte.is_ascii_digit())
                    && (part.as_bytes()[17].is_ascii_digit()
                        || matches!(part.as_bytes()[17], b'x' | b'X')))
        })
}

fn contains_phone_number(value: &str) -> bool {
    let mut digits = String::new();
    for character in value.chars().chain(std::iter::once('\0')) {
        if character.is_ascii_digit() {
            digits.push(character);
        } else if matches!(character, ' ' | '-' | '\u{2010}' | '\u{2011}') && !digits.is_empty() {
            continue;
        } else {
            if digits.len() == 11 && digits.starts_with('1') {
                return true;
            }
            digits.clear();
        }
    }
    false
}

fn contains_payment_card(value: &str) -> bool {
    let mut digits = String::new();
    for character in value.chars().chain(std::iter::once('\0')) {
        if character.is_ascii_digit() {
            digits.push(character);
        } else if matches!(character, ' ' | '-' | '\u{2010}' | '\u{2011}') && !digits.is_empty() {
            continue;
        } else {
            if (13..=19).contains(&digits.len()) && passes_luhn(&digits) {
                return true;
            }
            digits.clear();
        }
    }
    false
}

fn ascii_digit_runs(value: &str) -> impl Iterator<Item = &str> {
    value.split(|character: char| !character.is_ascii_digit())
}

fn has_ascii_digit_run(value: &str, minimum: usize, maximum: usize) -> bool {
    ascii_digit_runs(value).any(|digits| (minimum..=maximum).contains(&digits.len()))
}

fn passes_luhn(digits: &str) -> bool {
    let mut sum = 0_u32;
    let mut double = false;
    for byte in digits.bytes().rev() {
        let mut digit = u32::from(byte - b'0');
        if double {
            digit *= 2;
            if digit > 9 {
                digit -= 9;
            }
        }
        sum += digit;
        double = !double;
    }
    sum > 0 && sum.is_multiple_of(10)
}

fn text_units(value: &str) -> usize {
    value.chars().fold(0_usize, |total, character| {
        total.saturating_add(if character.is_ascii() { 1 } else { 2 })
    })
}

const fn privacy_rejection() -> AiError {
    AiError::new(AiErrorCode::InputRejectedByPrivacyGuard)
}
