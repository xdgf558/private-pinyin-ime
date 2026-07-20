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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u16)]
pub enum HelperOpcode {
    Authenticate = 1,
    Health = 2,
    MockInference = 3,
    Cancel = 4,
    Shutdown = 5,
    Authenticated = 0x8001,
    Healthy = 0x8002,
    MockCompleted = 0x8003,
    Cancelled = 0x8004,
    Acknowledged = 0x8005,
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
            0x8001 => Ok(Self::Authenticated),
            0x8002 => Ok(Self::Healthy),
            0x8003 => Ok(Self::MockCompleted),
            0x8004 => Ok(Self::Cancelled),
            0x8005 => Ok(Self::Acknowledged),
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
}
