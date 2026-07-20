#![forbid(unsafe_code)]

use std::collections::HashMap;
use std::env;
use std::io::{self, Read, Write};
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use private_pinyin_ai_helper_protocol::{
    decode_auth_token_hex, read_frame, write_frame, HelperAuthenticationGate, HelperErrorCode,
    HelperFrame, HelperIdlePolicy, HelperOpcode, HelperProtocolError, DEFAULT_HELPER_IDLE_TIMEOUT,
    MAX_HELPER_ACTIVE_REQUESTS, MAX_HELPER_RESPONSE_QUEUE,
};

#[cfg(windows)]
use std::fs::OpenOptions;

const TOKEN_ENVIRONMENT_KEY: &str = "PRIVATE_PINYIN_AI_HELPER_TOKEN";

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            // Error codes are content-free by contract. Never log a frame or payload.
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), HelperProtocolError> {
    let configuration = Configuration::parse(env::args().skip(1))?;
    let token_value =
        env::var(TOKEN_ENVIRONMENT_KEY).map_err(|_| HelperProtocolError::AuthenticationFailed)?;
    let token = decode_auth_token_hex(&token_value)?;
    env::remove_var(TOKEN_ENVIRONMENT_KEY);

    match configuration.transport {
        Transport::Stdio => serve(io::stdin(), io::stdout(), token, configuration.idle_timeout),
        Transport::NamedPipes { request, response } => {
            serve_named_pipes(&request, &response, token, configuration.idle_timeout)
        }
    }
}

struct Configuration {
    transport: Transport,
    idle_timeout: Duration,
}

enum Transport {
    Stdio,
    NamedPipes { request: String, response: String },
}

impl Configuration {
    fn parse(arguments: impl Iterator<Item = String>) -> Result<Self, HelperProtocolError> {
        let arguments: Vec<String> = arguments.collect();
        let mut transport = None;
        let mut request_pipe = None;
        let mut response_pipe = None;
        let mut idle_timeout = DEFAULT_HELPER_IDLE_TIMEOUT;
        let mut index = 0;
        while index < arguments.len() {
            match arguments[index].as_str() {
                "--stdio" if transport.is_none() => transport = Some(Transport::Stdio),
                "--request-pipe" if transport.is_none() && request_pipe.is_none() => {
                    index += 1;
                    let path = arguments
                        .get(index)
                        .filter(|value| !value.is_empty())
                        .ok_or(HelperProtocolError::InvalidPayload)?;
                    request_pipe = Some(path.clone());
                }
                "--response-pipe" if transport.is_none() && response_pipe.is_none() => {
                    index += 1;
                    let path = arguments
                        .get(index)
                        .filter(|value| !value.is_empty())
                        .ok_or(HelperProtocolError::InvalidPayload)?;
                    response_pipe = Some(path.clone());
                }
                "--idle-timeout-ms" => {
                    index += 1;
                    let millis = arguments
                        .get(index)
                        .ok_or(HelperProtocolError::InvalidPayload)?
                        .parse::<u64>()
                        .map_err(|_| HelperProtocolError::InvalidPayload)?;
                    idle_timeout = Duration::from_millis(millis);
                }
                _ => return Err(HelperProtocolError::InvalidPayload),
            }
            index += 1;
        }
        if transport.is_none() {
            let request = request_pipe.ok_or(HelperProtocolError::InvalidPayload)?;
            let response = response_pipe.ok_or(HelperProtocolError::InvalidPayload)?;
            if request == response {
                return Err(HelperProtocolError::InvalidPayload);
            }
            transport = Some(Transport::NamedPipes { request, response });
        } else if request_pipe.is_some() || response_pipe.is_some() {
            return Err(HelperProtocolError::InvalidPayload);
        }
        HelperIdlePolicy::new(idle_timeout, Instant::now())?;
        Ok(Self {
            transport: transport.ok_or(HelperProtocolError::InvalidPayload)?,
            idle_timeout,
        })
    }
}

#[cfg(windows)]
fn serve_named_pipes(
    request_path: &str,
    response_path: &str,
    token: [u8; 32],
    idle_timeout: Duration,
) -> Result<(), HelperProtocolError> {
    const PREFIX: &str = r"\\.\pipe\PrivatePinyinAI-";
    if !request_path.starts_with(PREFIX)
        || !request_path.ends_with("-request")
        || !response_path.starts_with(PREFIX)
        || !response_path.ends_with("-response")
        || request_path == response_path
    {
        return Err(HelperProtocolError::InvalidPayload);
    }
    // Two unidirectional pipe objects avoid the synchronous Windows pipe rule where
    // a pending read can block a writer that shares the same underlying file object.
    let reader = OpenOptions::new().read(true).open(request_path)?;
    let writer = OpenOptions::new().write(true).open(response_path)?;
    serve(reader, writer, token, idle_timeout)
}

#[cfg(not(windows))]
fn serve_named_pipes(
    _request_path: &str,
    _response_path: &str,
    _token: [u8; 32],
    _idle_timeout: Duration,
) -> Result<(), HelperProtocolError> {
    Err(HelperProtocolError::InvalidPayload)
}

fn serve(
    mut reader: impl Read + Send + 'static,
    writer: impl Write + Send + 'static,
    token: [u8; 32],
    idle_timeout: Duration,
) -> Result<(), HelperProtocolError> {
    let (response_tx, response_rx) = mpsc::sync_channel::<HelperFrame>(MAX_HELPER_RESPONSE_QUEUE);
    let writer_failed = Arc::new(AtomicBool::new(false));
    let writer_failed_for_thread = Arc::clone(&writer_failed);
    let writer_thread = thread::Builder::new()
        .name("private-pinyin-ai-helper-writer".to_string())
        .spawn(move || {
            let mut writer = writer;
            while let Ok(frame) = response_rx.recv() {
                if write_frame(&mut writer, &frame).is_err() {
                    writer_failed_for_thread.store(true, Ordering::Release);
                    break;
                }
            }
        })
        .map_err(|_| HelperProtocolError::Io(io::Error::other("writer thread")))?;

    let last_activity = Arc::new(Mutex::new(Instant::now()));
    let idle_expired = Arc::new(AtomicBool::new(false));
    let watchdog_activity = Arc::clone(&last_activity);
    let watchdog_expired = Arc::clone(&idle_expired);
    let watchdog = thread::Builder::new()
        .name("private-pinyin-ai-helper-idle".to_string())
        .spawn(move || idle_watchdog(watchdog_activity, watchdog_expired, idle_timeout))
        .map_err(|_| HelperProtocolError::Io(io::Error::other("idle thread")))?;

    let active = Arc::new(Mutex::new(HashMap::<u64, Arc<AtomicBool>>::new()));
    let mut worker_threads: Vec<JoinHandle<()>> = Vec::new();
    let mut authentication = HelperAuthenticationGate::new(token);
    let mut terminal_error = None;

    loop {
        if writer_failed.load(Ordering::Acquire) || idle_expired.load(Ordering::Acquire) {
            break;
        }
        let frame = match read_frame(&mut reader) {
            Ok(frame) => frame,
            Err(HelperProtocolError::Io(error)) if error.kind() == io::ErrorKind::UnexpectedEof => {
                break;
            }
            Err(error) => return Err(error),
        };
        touch(&last_activity);
        if let Err(error) = authentication.authorize(&frame) {
            let code = match error {
                HelperProtocolError::AuthenticationFailed => HelperErrorCode::AuthenticationFailed,
                HelperProtocolError::AuthenticationRequired => {
                    HelperErrorCode::AuthenticationRequired
                }
                _ => HelperErrorCode::InvalidPayload,
            };
            response_tx
                .send(HelperFrame::error(frame.request_id, code))
                .map_err(|_| HelperProtocolError::Io(io::Error::other("response channel")))?;
            terminal_error = Some(error);
            break;
        }
        if frame.opcode == HelperOpcode::Authenticate {
            response_tx
                .send(HelperFrame::empty(
                    HelperOpcode::Authenticated,
                    frame.request_id,
                ))
                .map_err(|_| HelperProtocolError::Io(io::Error::other("response channel")))?;
            continue;
        }

        match frame.opcode {
            HelperOpcode::Health => response_tx
                .send(HelperFrame::empty(HelperOpcode::Healthy, frame.request_id))
                .map_err(|_| HelperProtocolError::Io(io::Error::other("response channel")))?,
            HelperOpcode::MockInference => {
                let delay = match frame.mock_delay() {
                    Ok(delay) => delay,
                    Err(_) => {
                        response_tx
                            .send(HelperFrame::error(
                                frame.request_id,
                                HelperErrorCode::InvalidPayload,
                            ))
                            .map_err(|_| {
                                HelperProtocolError::Io(io::Error::other("response channel"))
                            })?;
                        continue;
                    }
                };
                let cancellation = Arc::new(AtomicBool::new(false));
                {
                    let mut requests = active.lock().map_err(|_| {
                        HelperProtocolError::Io(io::Error::other("active request lock"))
                    })?;
                    if requests.len() >= MAX_HELPER_ACTIVE_REQUESTS {
                        response_tx
                            .send(HelperFrame::error(
                                frame.request_id,
                                HelperErrorCode::QueueFull,
                            ))
                            .map_err(|_| {
                                HelperProtocolError::Io(io::Error::other("response channel"))
                            })?;
                        continue;
                    }
                    requests.insert(frame.request_id, Arc::clone(&cancellation));
                }
                worker_threads.push(spawn_mock(
                    frame.request_id,
                    delay,
                    cancellation,
                    Arc::clone(&active),
                    response_tx.clone(),
                    Arc::clone(&last_activity),
                )?);
            }
            HelperOpcode::Cancel => {
                let target = match frame.cancel_target() {
                    Ok(target) => target,
                    Err(_) => {
                        response_tx
                            .send(HelperFrame::error(
                                frame.request_id,
                                HelperErrorCode::InvalidPayload,
                            ))
                            .map_err(|_| {
                                HelperProtocolError::Io(io::Error::other("response channel"))
                            })?;
                        continue;
                    }
                };
                let cancellation = active
                    .lock()
                    .map_err(|_| HelperProtocolError::Io(io::Error::other("active request lock")))?
                    .get(&target)
                    .cloned();
                if let Some(cancellation) = cancellation {
                    cancellation.store(true, Ordering::Release);
                    response_tx
                        .send(HelperFrame::empty(HelperOpcode::Cancelled, target))
                        .map_err(|_| {
                            HelperProtocolError::Io(io::Error::other("response channel"))
                        })?;
                    response_tx
                        .send(HelperFrame::empty(
                            HelperOpcode::Acknowledged,
                            frame.request_id,
                        ))
                        .map_err(|_| {
                            HelperProtocolError::Io(io::Error::other("response channel"))
                        })?;
                } else {
                    response_tx
                        .send(HelperFrame::error(
                            frame.request_id,
                            HelperErrorCode::CancelTargetMissing,
                        ))
                        .map_err(|_| {
                            HelperProtocolError::Io(io::Error::other("response channel"))
                        })?;
                }
            }
            HelperOpcode::Shutdown => {
                cancel_all(&active);
                response_tx
                    .send(HelperFrame::empty(
                        HelperOpcode::Acknowledged,
                        frame.request_id,
                    ))
                    .map_err(|_| HelperProtocolError::Io(io::Error::other("response channel")))?;
                break;
            }
            _ => {
                response_tx
                    .send(HelperFrame::error(
                        frame.request_id,
                        HelperErrorCode::ProtocolMismatch,
                    ))
                    .map_err(|_| HelperProtocolError::Io(io::Error::other("response channel")))?;
            }
        }
    }

    cancel_all(&active);
    for worker in worker_threads {
        let _ = worker.join();
    }
    drop(response_tx);
    let _ = writer_thread.join();
    idle_expired.store(true, Ordering::Release);
    let _ = watchdog.join();
    match terminal_error {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

fn spawn_mock(
    request_id: u64,
    delay: Duration,
    cancellation: Arc<AtomicBool>,
    active: Arc<Mutex<HashMap<u64, Arc<AtomicBool>>>>,
    response_tx: SyncSender<HelperFrame>,
    last_activity: Arc<Mutex<Instant>>,
) -> Result<JoinHandle<()>, HelperProtocolError> {
    thread::Builder::new()
        .name("private-pinyin-ai-helper-mock".to_string())
        .spawn(move || {
            let started = Instant::now();
            while started.elapsed() < delay {
                if cancellation.load(Ordering::Acquire) {
                    remove_active(&active, request_id);
                    return;
                }
                thread::sleep(Duration::from_millis(5).min(delay));
            }
            if !cancellation.load(Ordering::Acquire) {
                let _ =
                    response_tx.send(HelperFrame::empty(HelperOpcode::MockCompleted, request_id));
                touch(&last_activity);
            }
            remove_active(&active, request_id);
        })
        .map_err(|_| HelperProtocolError::Io(io::Error::other("mock thread")))
}

fn remove_active(active: &Arc<Mutex<HashMap<u64, Arc<AtomicBool>>>>, request_id: u64) {
    if let Ok(mut active) = active.lock() {
        active.remove(&request_id);
    }
}

fn cancel_all(active: &Arc<Mutex<HashMap<u64, Arc<AtomicBool>>>>) {
    if let Ok(active) = active.lock() {
        for cancellation in active.values() {
            cancellation.store(true, Ordering::Release);
        }
    }
}

fn touch(last_activity: &Arc<Mutex<Instant>>) {
    if let Ok(mut last_activity) = last_activity.lock() {
        *last_activity = Instant::now();
    }
}

fn idle_watchdog(last_activity: Arc<Mutex<Instant>>, expired: Arc<AtomicBool>, timeout: Duration) {
    let interval = (timeout / 4).clamp(Duration::from_millis(10), Duration::from_secs(1));
    loop {
        thread::sleep(interval);
        if expired.load(Ordering::Acquire) {
            return;
        }
        let should_exit = last_activity
            .lock()
            .map(|last_activity| last_activity.elapsed() >= timeout)
            .unwrap_or(true);
        if should_exit {
            expired.store(true, Ordering::Release);
            // The reader may be blocked forever. Idle exit is an intentional process boundary.
            std::process::exit(0);
        }
    }
}

#[cfg(test)]
mod configuration_tests {
    use super::{Configuration, Transport};

    fn parse(arguments: &[&str]) -> Result<Configuration, String> {
        Configuration::parse(arguments.iter().map(|value| (*value).to_string()))
            .map_err(|error| error.to_string())
    }

    #[test]
    fn accepts_split_named_pipe_transport() {
        let configuration = parse(&[
            "--request-pipe",
            r"\\.\pipe\PrivatePinyinAI-test-request",
            "--response-pipe",
            r"\\.\pipe\PrivatePinyinAI-test-response",
            "--idle-timeout-ms",
            "15000",
        ])
        .expect("configuration");

        assert!(matches!(
            configuration.transport,
            Transport::NamedPipes { .. }
        ));
    }

    #[test]
    fn rejects_incomplete_or_ambiguous_pipe_transport() {
        assert!(parse(&["--request-pipe", r"\\.\pipe\PrivatePinyinAI-test-request"]).is_err());
        assert!(parse(&[
            "--request-pipe",
            r"\\.\pipe\PrivatePinyinAI-test",
            "--response-pipe",
            r"\\.\pipe\PrivatePinyinAI-test"
        ])
        .is_err());
        assert!(parse(&[
            "--stdio",
            "--response-pipe",
            r"\\.\pipe\PrivatePinyinAI-test-response"
        ])
        .is_err());
    }
}
