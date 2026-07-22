#![forbid(unsafe_code)]

use std::fmt;
use std::io::{self, Read, Write};
use std::time::{Duration, Instant};

pub const HELPER_PROTOCOL_MAGIC: u32 = 0x5050_4139;
pub const HELPER_PROTOCOL_VERSION: u16 = 1;
pub const HELPER_AUTH_TOKEN_BYTES: usize = 32;
pub const HELPER_FRAME_HEADER_BYTES: usize = 20;
pub const MAX_HELPER_PAYLOAD_BYTES: usize = 64 * 1024;
pub const MAX_HELPER_ACTIVE_REQUESTS: usize = 8;
pub const MAX_HELPER_RESPONSE_QUEUE: usize = 32;
pub const DEFAULT_HELPER_IDLE_TIMEOUT: Duration = Duration::from_secs(600);
pub const MAX_MOCK_DELAY: Duration = Duration::from_secs(5);
pub const WRITER_PAYLOAD_SCHEMA_VERSION: u16 = 1;
pub const MAX_WRITER_SOURCE_BYTES: usize = 4 * 1024;
pub const MAX_WRITER_SOURCE_CHARS: usize = 600;
pub const MAX_WRITER_SUGGESTIONS: usize = 3;
pub const MAX_WRITER_SUGGESTION_BYTES: usize = 4 * 1024;
pub const MAX_WRITER_SUGGESTION_CHARS: usize = 600;
pub const MAX_WRITER_DEADLINE: Duration = Duration::from_secs(3);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u16)]
pub enum HelperOpcode {
    Authenticate = 1,
    Health = 2,
    MockInference = 3,
    Cancel = 4,
    Shutdown = 5,
    WriterInference = 6,
    Authenticated = 0x8001,
    Healthy = 0x8002,
    MockCompleted = 0x8003,
    Cancelled = 0x8004,
    Acknowledged = 0x8005,
    WriterCompleted = 0x8006,
    Error = 0x80ff,
}

impl TryFrom<u16> for HelperOpcode {
    type Error = HelperProtocolError;

    fn try_from(value: u16) -> Result<Self, HelperProtocolError> {
        match value {
            1 => Ok(Self::Authenticate),
            2 => Ok(Self::Health),
            3 => Ok(Self::MockInference),
            4 => Ok(Self::Cancel),
            5 => Ok(Self::Shutdown),
            6 => Ok(Self::WriterInference),
            0x8001 => Ok(Self::Authenticated),
            0x8002 => Ok(Self::Healthy),
            0x8003 => Ok(Self::MockCompleted),
            0x8004 => Ok(Self::Cancelled),
            0x8005 => Ok(Self::Acknowledged),
            0x8006 => Ok(Self::WriterCompleted),
            0x80ff => Ok(Self::Error),
            _ => Err(HelperProtocolError::UnknownOpcode),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u16)]
pub enum HelperErrorCode {
    AuthenticationFailed = 1,
    AuthenticationRequired = 2,
    ProtocolMismatch = 3,
    InvalidPayload = 4,
    QueueFull = 5,
    CancelTargetMissing = 6,
    Internal = 7,
    ModelUnavailable = 8,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum WriterFeature {
    ShortCompletion = 1,
    RewriteFormal = 2,
    RewritePolite = 3,
    RewriteShort = 4,
    RewriteCasual = 5,
    TranslateZhEn = 6,
    TranslateEnZh = 7,
}

impl WriterFeature {
    pub const fn requires_explicit_action(self) -> bool {
        !matches!(self, Self::ShortCompletion)
    }
}

impl TryFrom<u8> for WriterFeature {
    type Error = HelperProtocolError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Self::ShortCompletion),
            2 => Ok(Self::RewriteFormal),
            3 => Ok(Self::RewritePolite),
            4 => Ok(Self::RewriteShort),
            5 => Ok(Self::RewriteCasual),
            6 => Ok(Self::TranslateZhEn),
            7 => Ok(Self::TranslateEnZh),
            _ => Err(HelperProtocolError::InvalidPayload),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WriterRequestIdentity {
    pub session_id: u64,
    pub revision: u64,
    pub candidate_set_hash: u64,
}

#[derive(Clone, PartialEq, Eq)]
pub struct WriterRequest {
    pub identity: WriterRequestIdentity,
    pub feature: WriterFeature,
    pub explicit_user_action: bool,
    pub deadline: Duration,
    locale: String,
    source: String,
}

impl WriterRequest {
    pub fn new(
        identity: WriterRequestIdentity,
        feature: WriterFeature,
        explicit_user_action: bool,
        deadline: Duration,
        locale: impl Into<String>,
        source: impl Into<String>,
    ) -> Result<Self, HelperProtocolError> {
        let request = Self {
            identity,
            feature,
            explicit_user_action,
            deadline,
            locale: locale.into(),
            source: source.into(),
        };
        request.validate()?;
        Ok(request)
    }

    pub fn locale(&self) -> &str {
        &self.locale
    }

    pub fn source(&self) -> &str {
        &self.source
    }

    fn validate(&self) -> Result<(), HelperProtocolError> {
        let valid_locale = !self.locale.is_empty()
            && self.locale.len() <= 32
            && self
                .locale
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-');
        let valid_source = !self.source.is_empty()
            && self.source.len() <= MAX_WRITER_SOURCE_BYTES
            && self.source.chars().count() <= MAX_WRITER_SOURCE_CHARS;
        let valid_deadline = !self.deadline.is_zero() && self.deadline <= MAX_WRITER_DEADLINE;
        if !valid_locale
            || !valid_source
            || !valid_deadline
            || (self.feature.requires_explicit_action() && !self.explicit_user_action)
        {
            return Err(HelperProtocolError::InvalidPayload);
        }
        Ok(())
    }
}

impl fmt::Debug for WriterRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("WriterRequest")
            .field("identity", &self.identity)
            .field("feature", &self.feature)
            .field("explicit_user_action", &self.explicit_user_action)
            .field("deadline", &self.deadline)
            .field("locale", &self.locale)
            .field("source", &"<redacted>")
            .field("source_bytes", &self.source.len())
            .finish()
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct WriterPreview {
    pub identity: WriterRequestIdentity,
    pub feature: WriterFeature,
    suggestions: Vec<String>,
}

impl WriterPreview {
    pub fn new(
        identity: WriterRequestIdentity,
        feature: WriterFeature,
        suggestions: Vec<String>,
    ) -> Result<Self, HelperProtocolError> {
        if suggestions.is_empty()
            || suggestions.len() > MAX_WRITER_SUGGESTIONS
            || suggestions.iter().any(|suggestion| {
                suggestion.is_empty()
                    || suggestion.len() > MAX_WRITER_SUGGESTION_BYTES
                    || suggestion.chars().count() > MAX_WRITER_SUGGESTION_CHARS
            })
        {
            return Err(HelperProtocolError::InvalidPayload);
        }
        Ok(Self {
            identity,
            feature,
            suggestions,
        })
    }

    pub fn suggestions(&self) -> &[String] {
        &self.suggestions
    }

    pub fn matches_request(&self, request: &WriterRequest) -> bool {
        self.identity == request.identity && self.feature == request.feature
    }
}

impl fmt::Debug for WriterPreview {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("WriterPreview")
            .field("identity", &self.identity)
            .field("feature", &self.feature)
            .field("suggestions", &"<redacted>")
            .field("suggestion_count", &self.suggestions.len())
            .finish()
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct HelperFrame {
    pub opcode: HelperOpcode,
    pub request_id: u64,
    payload: Vec<u8>,
}

impl HelperFrame {
    pub fn new(
        opcode: HelperOpcode,
        request_id: u64,
        payload: Vec<u8>,
    ) -> Result<Self, HelperProtocolError> {
        if payload.len() > MAX_HELPER_PAYLOAD_BYTES {
            return Err(HelperProtocolError::PayloadTooLarge);
        }
        Ok(Self {
            opcode,
            request_id,
            payload,
        })
    }

    pub fn empty(opcode: HelperOpcode, request_id: u64) -> Self {
        Self {
            opcode,
            request_id,
            payload: Vec::new(),
        }
    }

    pub fn error(request_id: u64, code: HelperErrorCode) -> Self {
        Self {
            opcode: HelperOpcode::Error,
            request_id,
            payload: (code as u16).to_le_bytes().to_vec(),
        }
    }

    pub fn cancel(request_id: u64, target_request_id: u64) -> Self {
        Self {
            opcode: HelperOpcode::Cancel,
            request_id,
            payload: target_request_id.to_le_bytes().to_vec(),
        }
    }

    pub fn mock(request_id: u64, delay: Duration) -> Result<Self, HelperProtocolError> {
        if delay > MAX_MOCK_DELAY {
            return Err(HelperProtocolError::InvalidPayload);
        }
        let millis =
            u32::try_from(delay.as_millis()).map_err(|_| HelperProtocolError::InvalidPayload)?;
        Self::new(
            HelperOpcode::MockInference,
            request_id,
            millis.to_le_bytes().to_vec(),
        )
    }

    pub fn writer(request_id: u64, request: &WriterRequest) -> Result<Self, HelperProtocolError> {
        Self::new(
            HelperOpcode::WriterInference,
            request_id,
            encode_writer_request(request)?,
        )
    }

    pub fn writer_completed(
        request_id: u64,
        preview: &WriterPreview,
    ) -> Result<Self, HelperProtocolError> {
        Self::new(
            HelperOpcode::WriterCompleted,
            request_id,
            encode_writer_preview(preview)?,
        )
    }

    pub fn payload(&self) -> &[u8] {
        &self.payload
    }

    pub fn cancel_target(&self) -> Result<u64, HelperProtocolError> {
        read_u64_payload(&self.payload)
    }

    pub fn mock_delay(&self) -> Result<Duration, HelperProtocolError> {
        if self.payload.len() != 4 {
            return Err(HelperProtocolError::InvalidPayload);
        }
        let millis = u32::from_le_bytes(
            self.payload
                .as_slice()
                .try_into()
                .map_err(|_| HelperProtocolError::InvalidPayload)?,
        );
        let delay = Duration::from_millis(u64::from(millis));
        if delay > MAX_MOCK_DELAY {
            return Err(HelperProtocolError::InvalidPayload);
        }
        Ok(delay)
    }

    pub fn writer_request(&self) -> Result<WriterRequest, HelperProtocolError> {
        if self.opcode != HelperOpcode::WriterInference {
            return Err(HelperProtocolError::InvalidPayload);
        }
        decode_writer_request(&self.payload)
    }

    pub fn writer_preview(&self) -> Result<WriterPreview, HelperProtocolError> {
        if self.opcode != HelperOpcode::WriterCompleted {
            return Err(HelperProtocolError::InvalidPayload);
        }
        decode_writer_preview(&self.payload)
    }
}

impl fmt::Debug for HelperFrame {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HelperFrame")
            .field("opcode", &self.opcode)
            .field("request_id", &self.request_id)
            .field("payload", &"<redacted>")
            .field("payload_len", &self.payload.len())
            .finish()
    }
}

#[derive(Debug)]
pub enum HelperProtocolError {
    Io(io::Error),
    InvalidMagic,
    VersionMismatch,
    UnknownOpcode,
    PayloadTooLarge,
    InvalidPayload,
    AuthenticationFailed,
    AuthenticationRequired,
}

impl fmt::Display for HelperProtocolError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::Io(_) => "AI_HELPER_IO_ERROR",
            Self::InvalidMagic => "AI_HELPER_INVALID_MAGIC",
            Self::VersionMismatch => "AI_HELPER_VERSION_MISMATCH",
            Self::UnknownOpcode => "AI_HELPER_UNKNOWN_OPCODE",
            Self::PayloadTooLarge => "AI_HELPER_PAYLOAD_TOO_LARGE",
            Self::InvalidPayload => "AI_HELPER_INVALID_PAYLOAD",
            Self::AuthenticationFailed => "AI_HELPER_AUTHENTICATION_FAILED",
            Self::AuthenticationRequired => "AI_HELPER_AUTHENTICATION_REQUIRED",
        };
        formatter.write_str(message)
    }
}

impl std::error::Error for HelperProtocolError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            _ => None,
        }
    }
}

impl From<io::Error> for HelperProtocolError {
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}

pub fn write_frame(
    writer: &mut impl Write,
    frame: &HelperFrame,
) -> Result<(), HelperProtocolError> {
    let payload_len =
        u32::try_from(frame.payload.len()).map_err(|_| HelperProtocolError::PayloadTooLarge)?;
    writer.write_all(&HELPER_PROTOCOL_MAGIC.to_le_bytes())?;
    writer.write_all(&HELPER_PROTOCOL_VERSION.to_le_bytes())?;
    writer.write_all(&(frame.opcode as u16).to_le_bytes())?;
    writer.write_all(&frame.request_id.to_le_bytes())?;
    writer.write_all(&payload_len.to_le_bytes())?;
    writer.write_all(&frame.payload)?;
    writer.flush()?;
    Ok(())
}

pub fn read_frame(reader: &mut impl Read) -> Result<HelperFrame, HelperProtocolError> {
    let mut header = [0_u8; HELPER_FRAME_HEADER_BYTES];
    reader.read_exact(&mut header)?;

    let magic = u32::from_le_bytes(header[0..4].try_into().expect("fixed magic slice"));
    if magic != HELPER_PROTOCOL_MAGIC {
        return Err(HelperProtocolError::InvalidMagic);
    }
    let version = u16::from_le_bytes(header[4..6].try_into().expect("fixed version slice"));
    if version != HELPER_PROTOCOL_VERSION {
        return Err(HelperProtocolError::VersionMismatch);
    }
    let opcode = HelperOpcode::try_from(u16::from_le_bytes(
        header[6..8].try_into().expect("fixed opcode slice"),
    ))?;
    let request_id = u64::from_le_bytes(
        header[8..16]
            .try_into()
            .expect("fixed request identifier slice"),
    );
    let payload_len = u32::from_le_bytes(
        header[16..20]
            .try_into()
            .expect("fixed payload length slice"),
    ) as usize;
    if payload_len > MAX_HELPER_PAYLOAD_BYTES {
        return Err(HelperProtocolError::PayloadTooLarge);
    }
    let mut payload = vec![0_u8; payload_len];
    reader.read_exact(&mut payload)?;
    HelperFrame::new(opcode, request_id, payload)
}

pub struct HelperAuthenticationGate {
    expected_token: [u8; HELPER_AUTH_TOKEN_BYTES],
    authenticated: bool,
}

impl HelperAuthenticationGate {
    pub const fn new(expected_token: [u8; HELPER_AUTH_TOKEN_BYTES]) -> Self {
        Self {
            expected_token,
            authenticated: false,
        }
    }

    pub fn authorize(&mut self, frame: &HelperFrame) -> Result<(), HelperProtocolError> {
        if !self.authenticated {
            if frame.opcode != HelperOpcode::Authenticate {
                return Err(HelperProtocolError::AuthenticationRequired);
            }
            if !constant_time_equal(frame.payload(), &self.expected_token) {
                return Err(HelperProtocolError::AuthenticationFailed);
            }
            self.authenticated = true;
            return Ok(());
        }
        if frame.opcode == HelperOpcode::Authenticate {
            return Err(HelperProtocolError::InvalidPayload);
        }
        Ok(())
    }

    pub const fn is_authenticated(&self) -> bool {
        self.authenticated
    }
}

pub struct HelperIdlePolicy {
    timeout: Duration,
    last_activity: Instant,
}

impl HelperIdlePolicy {
    pub fn new(timeout: Duration, now: Instant) -> Result<Self, HelperProtocolError> {
        if timeout.is_zero() || timeout > DEFAULT_HELPER_IDLE_TIMEOUT {
            return Err(HelperProtocolError::InvalidPayload);
        }
        Ok(Self {
            timeout,
            last_activity: now,
        })
    }

    pub fn touch(&mut self, now: Instant) {
        self.last_activity = now;
    }

    pub fn should_exit(&self, now: Instant) -> bool {
        now.saturating_duration_since(self.last_activity) >= self.timeout
    }

    pub const fn timeout(&self) -> Duration {
        self.timeout
    }
}

pub fn decode_auth_token_hex(
    value: &str,
) -> Result<[u8; HELPER_AUTH_TOKEN_BYTES], HelperProtocolError> {
    if value.len() != HELPER_AUTH_TOKEN_BYTES * 2 {
        return Err(HelperProtocolError::AuthenticationFailed);
    }
    let mut token = [0_u8; HELPER_AUTH_TOKEN_BYTES];
    for (index, byte) in token.iter_mut().enumerate() {
        let start = index * 2;
        *byte = u8::from_str_radix(&value[start..start + 2], 16)
            .map_err(|_| HelperProtocolError::AuthenticationFailed)?;
    }
    Ok(token)
}

fn constant_time_equal(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut difference = 0_u8;
    for (left_byte, right_byte) in left.iter().zip(right) {
        difference |= left_byte ^ right_byte;
    }
    difference == 0
}

fn read_u64_payload(payload: &[u8]) -> Result<u64, HelperProtocolError> {
    if payload.len() != 8 {
        return Err(HelperProtocolError::InvalidPayload);
    }
    Ok(u64::from_le_bytes(
        payload
            .try_into()
            .map_err(|_| HelperProtocolError::InvalidPayload)?,
    ))
}

fn encode_writer_request(request: &WriterRequest) -> Result<Vec<u8>, HelperProtocolError> {
    request.validate()?;
    let deadline_millis = u32::try_from(request.deadline.as_millis())
        .map_err(|_| HelperProtocolError::InvalidPayload)?;
    let locale_len =
        u16::try_from(request.locale.len()).map_err(|_| HelperProtocolError::InvalidPayload)?;
    let source_len =
        u32::try_from(request.source.len()).map_err(|_| HelperProtocolError::InvalidPayload)?;
    let mut payload = Vec::with_capacity(38 + request.locale.len() + request.source.len());
    payload.extend_from_slice(&WRITER_PAYLOAD_SCHEMA_VERSION.to_le_bytes());
    payload.push(request.feature as u8);
    payload.push(u8::from(request.explicit_user_action));
    payload.extend_from_slice(&request.identity.session_id.to_le_bytes());
    payload.extend_from_slice(&request.identity.revision.to_le_bytes());
    payload.extend_from_slice(&request.identity.candidate_set_hash.to_le_bytes());
    payload.extend_from_slice(&deadline_millis.to_le_bytes());
    payload.extend_from_slice(&locale_len.to_le_bytes());
    payload.extend_from_slice(&source_len.to_le_bytes());
    payload.extend_from_slice(request.locale.as_bytes());
    payload.extend_from_slice(request.source.as_bytes());
    Ok(payload)
}

fn decode_writer_request(payload: &[u8]) -> Result<WriterRequest, HelperProtocolError> {
    let mut reader = PayloadReader::new(payload);
    if reader.read_u16()? != WRITER_PAYLOAD_SCHEMA_VERSION {
        return Err(HelperProtocolError::VersionMismatch);
    }
    let feature = WriterFeature::try_from(reader.read_u8()?)?;
    let explicit_user_action = match reader.read_u8()? {
        0 => false,
        1 => true,
        _ => return Err(HelperProtocolError::InvalidPayload),
    };
    let identity = WriterRequestIdentity {
        session_id: reader.read_u64()?,
        revision: reader.read_u64()?,
        candidate_set_hash: reader.read_u64()?,
    };
    let deadline = Duration::from_millis(u64::from(reader.read_u32()?));
    let locale_len = usize::from(reader.read_u16()?);
    let source_len =
        usize::try_from(reader.read_u32()?).map_err(|_| HelperProtocolError::InvalidPayload)?;
    let locale = reader.read_string(locale_len)?;
    let source = reader.read_string(source_len)?;
    reader.finish()?;
    WriterRequest::new(
        identity,
        feature,
        explicit_user_action,
        deadline,
        locale,
        source,
    )
}

fn encode_writer_preview(preview: &WriterPreview) -> Result<Vec<u8>, HelperProtocolError> {
    let validated = WriterPreview::new(
        preview.identity,
        preview.feature,
        preview.suggestions.clone(),
    )?;
    let mut payload = Vec::new();
    payload.extend_from_slice(&WRITER_PAYLOAD_SCHEMA_VERSION.to_le_bytes());
    payload.push(validated.feature as u8);
    payload.push(
        u8::try_from(validated.suggestions.len())
            .map_err(|_| HelperProtocolError::InvalidPayload)?,
    );
    payload.extend_from_slice(&validated.identity.session_id.to_le_bytes());
    payload.extend_from_slice(&validated.identity.revision.to_le_bytes());
    payload.extend_from_slice(&validated.identity.candidate_set_hash.to_le_bytes());
    for suggestion in &validated.suggestions {
        let len =
            u16::try_from(suggestion.len()).map_err(|_| HelperProtocolError::InvalidPayload)?;
        payload.extend_from_slice(&len.to_le_bytes());
        payload.extend_from_slice(suggestion.as_bytes());
    }
    Ok(payload)
}

fn decode_writer_preview(payload: &[u8]) -> Result<WriterPreview, HelperProtocolError> {
    let mut reader = PayloadReader::new(payload);
    if reader.read_u16()? != WRITER_PAYLOAD_SCHEMA_VERSION {
        return Err(HelperProtocolError::VersionMismatch);
    }
    let feature = WriterFeature::try_from(reader.read_u8()?)?;
    let suggestion_count = usize::from(reader.read_u8()?);
    if suggestion_count == 0 || suggestion_count > MAX_WRITER_SUGGESTIONS {
        return Err(HelperProtocolError::InvalidPayload);
    }
    let identity = WriterRequestIdentity {
        session_id: reader.read_u64()?,
        revision: reader.read_u64()?,
        candidate_set_hash: reader.read_u64()?,
    };
    let mut suggestions = Vec::with_capacity(suggestion_count);
    for _ in 0..suggestion_count {
        let len = usize::from(reader.read_u16()?);
        suggestions.push(reader.read_string(len)?);
    }
    reader.finish()?;
    WriterPreview::new(identity, feature, suggestions)
}

struct PayloadReader<'a> {
    payload: &'a [u8],
    offset: usize,
}

impl<'a> PayloadReader<'a> {
    const fn new(payload: &'a [u8]) -> Self {
        Self { payload, offset: 0 }
    }

    fn read_u8(&mut self) -> Result<u8, HelperProtocolError> {
        Ok(self.read_bytes(1)?[0])
    }

    fn read_u16(&mut self) -> Result<u16, HelperProtocolError> {
        Ok(u16::from_le_bytes(
            self.read_bytes(2)?
                .try_into()
                .map_err(|_| HelperProtocolError::InvalidPayload)?,
        ))
    }

    fn read_u32(&mut self) -> Result<u32, HelperProtocolError> {
        Ok(u32::from_le_bytes(
            self.read_bytes(4)?
                .try_into()
                .map_err(|_| HelperProtocolError::InvalidPayload)?,
        ))
    }

    fn read_u64(&mut self) -> Result<u64, HelperProtocolError> {
        Ok(u64::from_le_bytes(
            self.read_bytes(8)?
                .try_into()
                .map_err(|_| HelperProtocolError::InvalidPayload)?,
        ))
    }

    fn read_string(&mut self, len: usize) -> Result<String, HelperProtocolError> {
        String::from_utf8(self.read_bytes(len)?.to_vec())
            .map_err(|_| HelperProtocolError::InvalidPayload)
    }

    fn read_bytes(&mut self, len: usize) -> Result<&'a [u8], HelperProtocolError> {
        let end = self
            .offset
            .checked_add(len)
            .ok_or(HelperProtocolError::InvalidPayload)?;
        let bytes = self
            .payload
            .get(self.offset..end)
            .ok_or(HelperProtocolError::InvalidPayload)?;
        self.offset = end;
        Ok(bytes)
    }

    fn finish(self) -> Result<(), HelperProtocolError> {
        if self.offset == self.payload.len() {
            Ok(())
        } else {
            Err(HelperProtocolError::InvalidPayload)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn token() -> [u8; HELPER_AUTH_TOKEN_BYTES] {
        [0x5a; HELPER_AUTH_TOKEN_BYTES]
    }

    #[test]
    fn frame_round_trip_is_bounded_and_redacted() {
        let frame = HelperFrame::new(HelperOpcode::MockInference, 42, b"private input".to_vec())
            .expect("bounded frame");
        let mut encoded = Vec::new();
        write_frame(&mut encoded, &frame).expect("write frame");
        let decoded = read_frame(&mut encoded.as_slice()).expect("read frame");
        assert_eq!(decoded, frame);
        let debug = format!("{decoded:?}");
        assert!(!debug.contains("private input"));
        assert!(debug.contains("<redacted>"));
    }

    #[test]
    fn oversized_frames_fail_before_allocation() {
        let mut encoded = Vec::new();
        encoded.extend_from_slice(&HELPER_PROTOCOL_MAGIC.to_le_bytes());
        encoded.extend_from_slice(&HELPER_PROTOCOL_VERSION.to_le_bytes());
        encoded.extend_from_slice(&(HelperOpcode::Health as u16).to_le_bytes());
        encoded.extend_from_slice(&1_u64.to_le_bytes());
        encoded.extend_from_slice(&((MAX_HELPER_PAYLOAD_BYTES as u32) + 1).to_le_bytes());
        assert!(matches!(
            read_frame(&mut encoded.as_slice()),
            Err(HelperProtocolError::PayloadTooLarge)
        ));
    }

    #[test]
    fn maximum_sized_frame_round_trips_at_the_exact_boundary() {
        let frame = HelperFrame::new(
            HelperOpcode::Health,
            64,
            vec![0x5a; MAX_HELPER_PAYLOAD_BYTES],
        )
        .expect("maximum bounded frame");
        let mut encoded = Vec::new();
        write_frame(&mut encoded, &frame).expect("write maximum frame");
        assert_eq!(
            encoded.len(),
            HELPER_FRAME_HEADER_BYTES + MAX_HELPER_PAYLOAD_BYTES
        );
        assert_eq!(
            read_frame(&mut encoded.as_slice()).expect("read maximum frame"),
            frame
        );
    }

    #[test]
    fn authentication_fails_closed_and_cannot_repeat() {
        let mut gate = HelperAuthenticationGate::new(token());
        assert!(matches!(
            gate.authorize(&HelperFrame::empty(HelperOpcode::Health, 1)),
            Err(HelperProtocolError::AuthenticationRequired)
        ));
        assert!(matches!(
            gate.authorize(
                &HelperFrame::new(HelperOpcode::Authenticate, 0, vec![0; 32])
                    .expect("bad token frame")
            ),
            Err(HelperProtocolError::AuthenticationFailed)
        ));
        gate.authorize(
            &HelperFrame::new(HelperOpcode::Authenticate, 0, token().to_vec()).expect("auth frame"),
        )
        .expect("matching token");
        assert!(gate.is_authenticated());
        assert!(matches!(
            gate.authorize(
                &HelperFrame::new(HelperOpcode::Authenticate, 0, token().to_vec())
                    .expect("repeat auth frame")
            ),
            Err(HelperProtocolError::InvalidPayload)
        ));
    }

    #[test]
    fn idle_policy_uses_a_strict_bounded_timeout() {
        let start = Instant::now();
        let mut policy =
            HelperIdlePolicy::new(Duration::from_secs(10), start).expect("valid idle timeout");
        assert!(!policy.should_exit(start + Duration::from_secs(9)));
        assert!(policy.should_exit(start + Duration::from_secs(10)));
        policy.touch(start + Duration::from_secs(10));
        assert!(!policy.should_exit(start + Duration::from_secs(19)));
        assert!(HelperIdlePolicy::new(Duration::ZERO, start).is_err());
        assert!(HelperIdlePolicy::new(Duration::from_secs(601), start).is_err());
    }

    #[test]
    fn mock_and_cancel_payloads_are_validated() {
        let mock = HelperFrame::mock(8, Duration::from_millis(250)).expect("mock request");
        assert_eq!(
            mock.mock_delay().expect("mock delay"),
            Duration::from_millis(250)
        );
        let cancel = HelperFrame::cancel(9, 8);
        assert_eq!(cancel.cancel_target().expect("cancel target"), 8);
        assert!(HelperFrame::mock(1, Duration::from_secs(6)).is_err());
    }

    #[test]
    fn writer_request_round_trip_is_bounded_versioned_and_redacted() {
        let identity = WriterRequestIdentity {
            session_id: 7,
            revision: 11,
            candidate_set_hash: 13,
        };
        let request = WriterRequest::new(
            identity,
            WriterFeature::RewritePolite,
            true,
            Duration::from_secs(3),
            "zh-CN",
            "请重写这条私密内容",
        )
        .expect("writer request");
        let frame = HelperFrame::writer(19, &request).expect("writer frame");
        let decoded = frame.writer_request().expect("decoded writer request");

        assert_eq!(decoded, request);
        assert!(!format!("{decoded:?}").contains("私密内容"));
    }

    #[test]
    fn writer_explicit_actions_and_content_bounds_fail_closed() {
        let identity = WriterRequestIdentity {
            session_id: 1,
            revision: 2,
            candidate_set_hash: 3,
        };
        assert!(WriterRequest::new(
            identity,
            WriterFeature::TranslateZhEn,
            false,
            Duration::from_secs(3),
            "zh-CN",
            "翻译",
        )
        .is_err());
        assert!(WriterRequest::new(
            identity,
            WriterFeature::ShortCompletion,
            false,
            Duration::from_millis(800),
            "zh-CN",
            "字".repeat(MAX_WRITER_SOURCE_CHARS + 1),
        )
        .is_err());
        assert!(WriterRequest::new(
            identity,
            WriterFeature::ShortCompletion,
            false,
            MAX_WRITER_DEADLINE + Duration::from_millis(1),
            "zh-CN",
            "继续",
        )
        .is_err());
    }

    #[test]
    fn writer_preview_requires_complete_identity_and_never_logs_text() {
        let identity = WriterRequestIdentity {
            session_id: 21,
            revision: 22,
            candidate_set_hash: 23,
        };
        let request = WriterRequest::new(
            identity,
            WriterFeature::ShortCompletion,
            false,
            Duration::from_millis(800),
            "zh-CN",
            "周末我们一起",
        )
        .expect("writer request");
        let preview = WriterPreview::new(
            identity,
            WriterFeature::ShortCompletion,
            vec!["周末我们一起吃饭".to_owned(), "周末我们一起散步".to_owned()],
        )
        .expect("writer preview");
        let frame = HelperFrame::writer_completed(24, &preview).expect("preview frame");
        let decoded = frame.writer_preview().expect("decoded preview");

        assert!(decoded.matches_request(&request));
        assert_eq!(decoded.suggestions().len(), 2);
        assert!(!format!("{decoded:?}").contains("一起吃饭"));

        let stale_request = WriterRequest::new(
            WriterRequestIdentity {
                revision: identity.revision + 1,
                ..identity
            },
            WriterFeature::ShortCompletion,
            false,
            Duration::from_millis(800),
            "zh-CN",
            "周末我们一起",
        )
        .expect("stale request");
        assert!(!decoded.matches_request(&stale_request));
    }

    #[test]
    fn writer_decoder_rejects_trailing_or_truncated_payloads() {
        let request = WriterRequest::new(
            WriterRequestIdentity {
                session_id: 1,
                revision: 1,
                candidate_set_hash: 1,
            },
            WriterFeature::ShortCompletion,
            false,
            Duration::from_millis(800),
            "zh-CN",
            "继续",
        )
        .expect("writer request");
        let frame = HelperFrame::writer(1, &request).expect("writer frame");
        let mut trailing = frame.payload().to_vec();
        trailing.push(0);
        let trailing = HelperFrame::new(HelperOpcode::WriterInference, 1, trailing)
            .expect("bounded malformed frame");
        assert!(trailing.writer_request().is_err());

        let truncated = HelperFrame::new(
            HelperOpcode::WriterInference,
            1,
            frame.payload()[..frame.payload().len() - 1].to_vec(),
        )
        .expect("bounded truncated frame");
        assert!(truncated.writer_request().is_err());
    }
}
