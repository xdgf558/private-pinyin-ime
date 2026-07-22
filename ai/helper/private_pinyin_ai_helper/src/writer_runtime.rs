use std::collections::HashSet;
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use private_pinyin_ai_helper_protocol::{
    WriterFeature, WriterRequest, MAX_WRITER_SUGGESTIONS, MAX_WRITER_SUGGESTION_BYTES,
    MAX_WRITER_SUGGESTION_CHARS,
};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;

pub const WRITER_MODEL_ID: &str = "qwen2.5-1.5b-instruct-q4-k-m";
pub const WRITER_MODEL_FILENAME: &str = "qwen2.5-1.5b-instruct-q4_k_m.gguf";
pub const WRITER_MODEL_SIZE_BYTES: u64 = 1_117_320_736;
pub const WRITER_MODEL_SHA256: &str =
    "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e";

const MAX_HTTP_RESPONSE_BYTES: u64 = 128 * 1024;
const SERVER_START_ATTEMPTS: usize = 2;
const SERVER_POLL_INTERVAL: Duration = Duration::from_millis(25);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WriterRuntimeError {
    ModelUnavailable,
    DeadlineExceeded,
    Cancelled,
    InferenceFailed,
}

struct ServerProcess {
    child: Child,
    address: SocketAddr,
    api_key: String,
    // Retained only when immediate removal failed (for example, a transient
    // Windows file-share race); Drop retries without exposing the key in argv.
    _api_key_file: ApiKeyFile,
}

pub struct WriterRuntime {
    server: Option<ServerProcess>,
}

impl WriterRuntime {
    pub fn new() -> Self {
        Self { server: None }
    }

    pub fn infer(
        &mut self,
        request: &WriterRequest,
        timeout: Duration,
        cancellation: &AtomicBool,
    ) -> Result<Vec<String>, WriterRuntimeError> {
        let started = Instant::now();
        if cancellation.load(Ordering::Acquire) {
            return Err(WriterRuntimeError::Cancelled);
        }
        self.ensure_server(timeout, cancellation)?;
        let remaining = timeout
            .checked_sub(started.elapsed())
            .ok_or(WriterRuntimeError::DeadlineExceeded)?;
        if remaining.is_zero() {
            return Err(WriterRuntimeError::DeadlineExceeded);
        }

        let server = self
            .server
            .as_mut()
            .ok_or(WriterRuntimeError::ModelUnavailable)?;
        if server
            .child
            .try_wait()
            .map_err(|_| WriterRuntimeError::InferenceFailed)?
            .is_some()
        {
            self.server = None;
            return Err(WriterRuntimeError::ModelUnavailable);
        }

        let suggestions =
            request_writer_preview(server.address, &server.api_key, request, remaining)?;
        if cancellation.load(Ordering::Acquire) {
            return Err(WriterRuntimeError::Cancelled);
        }
        Ok(suggestions)
    }

    pub fn prepare(
        &mut self,
        timeout: Duration,
        cancellation: &AtomicBool,
    ) -> Result<(), WriterRuntimeError> {
        self.ensure_server(timeout, cancellation)
    }

    fn ensure_server(
        &mut self,
        timeout: Duration,
        cancellation: &AtomicBool,
    ) -> Result<(), WriterRuntimeError> {
        if let Some(server) = self.server.as_mut() {
            if server
                .child
                .try_wait()
                .map_err(|_| WriterRuntimeError::InferenceFailed)?
                .is_none()
            {
                return Ok(());
            }
            self.server = None;
        }

        let deadline = Instant::now() + timeout;
        let model_path = installed_model_path().ok_or(WriterRuntimeError::ModelUnavailable)?;
        verify_model(&model_path, deadline, cancellation)?;
        let executable = runtime_executable_path().ok_or(WriterRuntimeError::ModelUnavailable)?;
        if !executable.is_file() {
            return Err(WriterRuntimeError::ModelUnavailable);
        }

        for _ in 0..SERVER_START_ATTEMPTS {
            if cancellation.load(Ordering::Acquire) {
                return Err(WriterRuntimeError::Cancelled);
            }
            let address = reserve_loopback_address()?;
            let api_key = generate_server_api_key()?;
            let mut api_key_file = ApiKeyFile::create(&model_path, &api_key)?;
            let mut child = spawn_server(&executable, &model_path, address, api_key_file.path())?;
            while Instant::now() < deadline {
                if cancellation.load(Ordering::Acquire) {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(WriterRuntimeError::Cancelled);
                }
                if child
                    .try_wait()
                    .map_err(|_| WriterRuntimeError::InferenceFailed)?
                    .is_some()
                {
                    break;
                }
                let remaining = deadline.saturating_duration_since(Instant::now());
                if remaining.is_zero() {
                    break;
                }
                if server_is_ready(address, &api_key, remaining.min(Duration::from_millis(200))) {
                    api_key_file.remove_now();
                    self.server = Some(ServerProcess {
                        child,
                        address,
                        api_key,
                        _api_key_file: api_key_file,
                    });
                    return Ok(());
                }
                std::thread::sleep(SERVER_POLL_INTERVAL.min(remaining));
            }
            let _ = child.kill();
            let _ = child.wait();
        }
        if Instant::now() >= deadline {
            Err(WriterRuntimeError::DeadlineExceeded)
        } else {
            Err(WriterRuntimeError::ModelUnavailable)
        }
    }
}

impl Drop for WriterRuntime {
    fn drop(&mut self) {
        if let Some(server) = self.server.as_mut() {
            let _ = server.child.kill();
            let _ = server.child.wait();
        }
    }
}

fn installed_model_path() -> Option<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        let home = env::var_os("HOME")?;
        Some(
            PathBuf::from(home)
                .join("Library/Application Support/PrivatePinyin/WriterModels")
                .join(WRITER_MODEL_ID)
                .join(WRITER_MODEL_FILENAME),
        )
    }
    #[cfg(windows)]
    {
        let local_app_data = env::var_os("LOCALAPPDATA")?;
        Some(
            PathBuf::from(local_app_data)
                .join("PrivatePinyin/WriterModels")
                .join(WRITER_MODEL_ID)
                .join(WRITER_MODEL_FILENAME),
        )
    }
    #[cfg(all(not(target_os = "macos"), not(windows)))]
    {
        let data_home = env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/share")))?;
        Some(
            data_home
                .join("PrivatePinyin/WriterModels")
                .join(WRITER_MODEL_ID)
                .join(WRITER_MODEL_FILENAME),
        )
    }
}

fn runtime_executable_path() -> Option<PathBuf> {
    let executable = env::current_exe().ok()?;
    let name = if cfg!(windows) {
        "llama-server.exe"
    } else {
        "llama-server"
    };
    Some(executable.parent()?.join("WriterRuntime").join(name))
}

fn verify_model(
    path: &Path,
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<(), WriterRuntimeError> {
    check_cancelled_or_expired(deadline, cancellation)?;
    let metadata = path
        .metadata()
        .map_err(|_| WriterRuntimeError::ModelUnavailable)?;
    if !metadata.is_file() || metadata.len() != WRITER_MODEL_SIZE_BYTES {
        return Err(WriterRuntimeError::ModelUnavailable);
    }
    let mut file = File::open(path).map_err(|_| WriterRuntimeError::ModelUnavailable)?;
    let digest = hash_reader(&mut file, deadline, cancellation)?;
    if digest != WRITER_MODEL_SHA256 {
        return Err(WriterRuntimeError::ModelUnavailable);
    }
    Ok(())
}

fn hash_reader<R: Read>(
    mut reader: R,
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<String, WriterRuntimeError> {
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 1024 * 1024];
    loop {
        check_cancelled_or_expired(deadline, cancellation)?;
        let count = reader
            .read(&mut buffer)
            .map_err(|_| WriterRuntimeError::ModelUnavailable)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    check_cancelled_or_expired(deadline, cancellation)?;
    Ok(hexadecimal(&hasher.finalize()))
}

fn check_cancelled_or_expired(
    deadline: Instant,
    cancellation: &AtomicBool,
) -> Result<(), WriterRuntimeError> {
    if cancellation.load(Ordering::Acquire) {
        Err(WriterRuntimeError::Cancelled)
    } else if Instant::now() >= deadline {
        Err(WriterRuntimeError::DeadlineExceeded)
    } else {
        Ok(())
    }
}

struct ApiKeyFile {
    path: Option<PathBuf>,
}

impl ApiKeyFile {
    fn create(model_path: &Path, api_key: &str) -> Result<Self, WriterRuntimeError> {
        let directory = model_path
            .parent()
            .ok_or(WriterRuntimeError::ModelUnavailable)?;
        for _ in 0..4 {
            let mut suffix = [0_u8; 16];
            getrandom::fill(&mut suffix).map_err(|_| WriterRuntimeError::ModelUnavailable)?;
            let path = directory.join(format!(".llama-api-key-{}.tmp", hexadecimal(&suffix)));
            let mut options = OpenOptions::new();
            options.write(true).create_new(true);
            #[cfg(unix)]
            options.mode(0o600);
            let mut file = match options.open(&path) {
                Ok(file) => file,
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(_) => return Err(WriterRuntimeError::ModelUnavailable),
            };
            if writeln!(file, "{api_key}").is_err() || file.sync_all().is_err() {
                let _ = fs::remove_file(&path);
                return Err(WriterRuntimeError::ModelUnavailable);
            }
            return Ok(Self { path: Some(path) });
        }
        Err(WriterRuntimeError::ModelUnavailable)
    }

    fn path(&self) -> &Path {
        self.path.as_deref().expect("API key file is present")
    }

    fn remove_now(&mut self) {
        let Some(path) = self.path.as_ref() else {
            return;
        };
        if fs::remove_file(path).is_ok() {
            self.path = None;
        }
    }
}

impl Drop for ApiKeyFile {
    fn drop(&mut self) {
        if let Some(path) = self.path.take() {
            let _ = fs::remove_file(path);
        }
    }
}

fn generate_server_api_key() -> Result<String, WriterRuntimeError> {
    let mut key = [0_u8; 32];
    getrandom::fill(&mut key).map_err(|_| WriterRuntimeError::ModelUnavailable)?;
    Ok(hexadecimal(&key))
}

fn reserve_loopback_address() -> Result<SocketAddr, WriterRuntimeError> {
    let listener = TcpListener::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0))
        .map_err(|_| WriterRuntimeError::ModelUnavailable)?;
    listener
        .local_addr()
        .map_err(|_| WriterRuntimeError::ModelUnavailable)
}

fn spawn_server(
    executable: &Path,
    model_path: &Path,
    address: SocketAddr,
    api_key_file: &Path,
) -> Result<Child, WriterRuntimeError> {
    Command::new(executable)
        .args([
            "--model",
            &model_path.to_string_lossy(),
            "--host",
            "127.0.0.1",
            "--port",
            &address.port().to_string(),
            "--api-key-file",
            &api_key_file.to_string_lossy(),
            "--no-webui",
            "--offline",
            "--log-disable",
            "--parallel",
            "1",
            "--ctx-size",
            "2048",
            "--batch-size",
            "256",
            "--ubatch-size",
            "128",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| WriterRuntimeError::ModelUnavailable)
}

fn server_is_ready(address: SocketAddr, api_key: &str, timeout: Duration) -> bool {
    let request = format!(
        "GET /health HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {}\r\nConnection: close\r\n\r\n",
        address, api_key
    );
    http_request(address, request.as_bytes(), timeout)
        .map(|response| response.status == 200)
        .unwrap_or(false)
}

fn request_writer_preview(
    address: SocketAddr,
    api_key: &str,
    request: &WriterRequest,
    timeout: Duration,
) -> Result<Vec<String>, WriterRuntimeError> {
    let body = json!({
        "model": WRITER_MODEL_ID,
        "messages": [
            {"role": "system", "content": system_prompt(request.feature)},
            {"role": "user", "content": request.source()}
        ],
        "temperature": if matches!(request.feature, WriterFeature::ShortCompletion) { 0.45 } else { 0.2 },
        "top_p": 0.9,
        "max_tokens": 512,
        "stream": false
    })
    .to_string();
    let wire = format!(
        "POST /v1/chat/completions HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        address,
        api_key,
        body.len(),
        body
    );
    let response = http_request(address, wire.as_bytes(), timeout)?;
    if response.status != 200 {
        return Err(WriterRuntimeError::InferenceFailed);
    }
    let value: Value =
        serde_json::from_slice(&response.body).map_err(|_| WriterRuntimeError::InferenceFailed)?;
    let content = value
        .pointer("/choices/0/message/content")
        .and_then(Value::as_str)
        .ok_or(WriterRuntimeError::InferenceFailed)?;
    parse_suggestions(content, request.source())
}

fn system_prompt(feature: WriterFeature) -> &'static str {
    match feature {
        WriterFeature::ShortCompletion => {
            "你是离线中文输入法的短补全器。根据用户当前文本，给出1到3个简短、自然、可直接追加的后续片段，不要重复原文。只输出JSON对象，格式为 {\"suggestions\":[\"片段1\",\"片段2\"]}，不要解释。"
        }
        WriterFeature::RewriteFormal => {
            "将用户文本改写得正式、准确，保持原意。给出1到3个完整改写。只输出JSON对象，格式为 {\"suggestions\":[\"改写1\",\"改写2\"]}，不要解释。"
        }
        WriterFeature::RewritePolite => {
            "将用户文本改写得礼貌、自然，保持原意。给出1到3个完整改写。只输出JSON对象，格式为 {\"suggestions\":[\"改写1\",\"改写2\"]}，不要解释。"
        }
        WriterFeature::RewriteShort => {
            "压缩用户文本，使其更简洁但不丢失关键信息。给出1到3个完整改写。只输出JSON对象，格式为 {\"suggestions\":[\"改写1\",\"改写2\"]}，不要解释。"
        }
        WriterFeature::RewriteCasual => {
            "将用户文本改写得轻松、口语化，保持原意。给出1到3个完整改写。只输出JSON对象，格式为 {\"suggestions\":[\"改写1\",\"改写2\"]}，不要解释。"
        }
        WriterFeature::TranslateZhEn => {
            "把用户的中文准确翻译成自然英文。给出1到3个完整译文。只输出JSON对象，格式为 {\"suggestions\":[\"translation 1\",\"translation 2\"]}，不要解释。"
        }
        WriterFeature::TranslateEnZh => {
            "把用户的英文准确翻译成自然简体中文。给出1到3个完整译文。只输出JSON对象，格式为 {\"suggestions\":[\"译文1\",\"译文2\"]}，不要解释。"
        }
    }
}

fn parse_suggestions(content: &str, source: &str) -> Result<Vec<String>, WriterRuntimeError> {
    let trimmed = content.trim();
    let json_text = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .unwrap_or(trimmed)
        .strip_suffix("```")
        .unwrap_or(trimmed)
        .trim();
    let parsed: Value =
        serde_json::from_str(json_text).map_err(|_| WriterRuntimeError::InferenceFailed)?;
    let values = parsed
        .get("suggestions")
        .and_then(Value::as_array)
        .or_else(|| parsed.as_array())
        .ok_or(WriterRuntimeError::InferenceFailed)?;
    let mut seen = HashSet::new();
    let suggestions: Vec<String> = values
        .iter()
        .filter_map(Value::as_str)
        .map(str::trim)
        .filter(|value| {
            !value.is_empty()
                && *value != source
                && value.len() <= MAX_WRITER_SUGGESTION_BYTES
                && value.chars().count() <= MAX_WRITER_SUGGESTION_CHARS
        })
        .filter(|value| seen.insert((*value).to_string()))
        .take(MAX_WRITER_SUGGESTIONS)
        .map(str::to_string)
        .collect();
    if suggestions.is_empty() {
        Err(WriterRuntimeError::InferenceFailed)
    } else {
        Ok(suggestions)
    }
}

struct HttpResponse {
    status: u16,
    body: Vec<u8>,
}

fn http_request(
    address: SocketAddr,
    request: &[u8],
    timeout: Duration,
) -> Result<HttpResponse, WriterRuntimeError> {
    if timeout.is_zero() {
        return Err(WriterRuntimeError::DeadlineExceeded);
    }
    let started = Instant::now();
    let mut stream = TcpStream::connect_timeout(&address, timeout).map_err(map_network_error)?;
    let remaining = timeout
        .checked_sub(started.elapsed())
        .ok_or(WriterRuntimeError::DeadlineExceeded)?;
    stream
        .set_read_timeout(Some(remaining))
        .map_err(|_| WriterRuntimeError::InferenceFailed)?;
    stream
        .set_write_timeout(Some(remaining))
        .map_err(|_| WriterRuntimeError::InferenceFailed)?;
    stream.write_all(request).map_err(map_network_error)?;
    let mut response = Vec::new();
    stream
        .take(MAX_HTTP_RESPONSE_BYTES)
        .read_to_end(&mut response)
        .map_err(map_network_error)?;
    parse_http_response(&response)
}

fn map_network_error(error: io::Error) -> WriterRuntimeError {
    if matches!(
        error.kind(),
        io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock
    ) {
        WriterRuntimeError::DeadlineExceeded
    } else {
        WriterRuntimeError::InferenceFailed
    }
}

fn parse_http_response(response: &[u8]) -> Result<HttpResponse, WriterRuntimeError> {
    let split = response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .ok_or(WriterRuntimeError::InferenceFailed)?;
    let header =
        std::str::from_utf8(&response[..split]).map_err(|_| WriterRuntimeError::InferenceFailed)?;
    let status = header
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|status| status.parse::<u16>().ok())
        .ok_or(WriterRuntimeError::InferenceFailed)?;
    Ok(HttpResponse {
        status,
        body: response[split + 4..].to_vec(),
    })
}

fn hexadecimal(bytes: &[u8]) -> String {
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        let _ = write!(&mut output, "{byte:02x}");
    }
    output
}

#[cfg(test)]
mod tests {
    use super::{
        check_cancelled_or_expired, generate_server_api_key, hash_reader, parse_http_response,
        parse_suggestions, system_prompt, ApiKeyFile, WriterRuntime, WriterRuntimeError,
    };
    use private_pinyin_ai_helper_protocol::WriterFeature;
    use std::fs;
    use std::io::{self, Cursor, Read};
    use std::path::PathBuf;
    use std::sync::atomic::AtomicBool;
    use std::time::{Duration, Instant};

    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;

    struct CancellingReader<'a> {
        inner: Cursor<Vec<u8>>,
        cancellation: &'a AtomicBool,
        completed_reads: usize,
    }

    impl Read for CancellingReader<'_> {
        fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
            let count = self.inner.read(buffer)?;
            if count > 0 {
                self.completed_reads += 1;
                if self.completed_reads == 1 {
                    self.cancellation
                        .store(true, std::sync::atomic::Ordering::Release);
                }
            }
            Ok(count)
        }
    }

    #[test]
    fn server_api_key_is_generated_independently_from_helper_authentication() {
        let first = generate_server_api_key().expect("first key");
        let second = generate_server_api_key().expect("second key");
        assert_eq!(first.len(), 64);
        assert_eq!(second.len(), 64);
        assert_ne!(first, second);
        let _runtime = WriterRuntime::new();
    }

    #[test]
    fn server_api_key_file_is_private_and_removed_after_startup() {
        let directory = temporary_test_directory("api-key-file");
        fs::create_dir(&directory).expect("temporary directory");
        let model_path = directory.join("model.gguf");
        let key = generate_server_api_key().expect("server key");
        let mut key_file = ApiKeyFile::create(&model_path, &key).expect("API key file");
        let key_path = key_file.path().to_path_buf();
        assert_eq!(
            fs::read_to_string(&key_path).expect("key contents"),
            format!("{key}\n")
        );
        assert!(!key_path.to_string_lossy().contains(&key));
        #[cfg(unix)]
        assert_eq!(
            fs::metadata(&key_path)
                .expect("key metadata")
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        key_file.remove_now();
        assert!(!key_path.exists());
        fs::remove_dir(directory).expect("remove temporary directory");
    }

    #[test]
    fn model_hashing_observes_cancellation_between_chunks() {
        let cancellation = AtomicBool::new(false);
        let reader = CancellingReader {
            inner: Cursor::new(vec![7_u8; 2 * 1024 * 1024]),
            cancellation: &cancellation,
            completed_reads: 0,
        };
        assert_eq!(
            hash_reader(
                reader,
                Instant::now() + Duration::from_secs(1),
                &cancellation
            ),
            Err(WriterRuntimeError::Cancelled)
        );
    }

    #[test]
    fn cancellation_and_deadline_interrupt_long_running_preparation() {
        let cancelled = AtomicBool::new(true);
        assert_eq!(
            check_cancelled_or_expired(Instant::now() + Duration::from_secs(1), &cancelled),
            Err(WriterRuntimeError::Cancelled)
        );
        let active = AtomicBool::new(false);
        assert_eq!(
            check_cancelled_or_expired(Instant::now(), &active),
            Err(WriterRuntimeError::DeadlineExceeded)
        );
    }

    fn temporary_test_directory(label: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "private-pinyin-{label}-{}",
            generate_server_api_key().expect("temporary suffix")
        ))
    }

    #[test]
    fn parses_bounded_deduplicated_suggestions() {
        let suggestions = parse_suggestions(
            r#"{"suggestions":["您好","您好","你好","原文","第三条"]}"#,
            "原文",
        )
        .expect("suggestions");
        assert_eq!(suggestions, vec!["您好", "你好", "第三条"]);
    }

    #[test]
    fn accepts_json_code_fence_and_rejects_free_form_text() {
        assert_eq!(
            parse_suggestions("```json\n[\"继续\"]\n```", "开始").expect("fenced"),
            vec!["继续"]
        );
        assert_eq!(
            parse_suggestions("继续", "开始"),
            Err(WriterRuntimeError::InferenceFailed)
        );
    }

    #[test]
    fn every_writer_feature_uses_a_json_only_prompt() {
        let features = [
            WriterFeature::ShortCompletion,
            WriterFeature::RewriteFormal,
            WriterFeature::RewritePolite,
            WriterFeature::RewriteShort,
            WriterFeature::RewriteCasual,
            WriterFeature::TranslateZhEn,
            WriterFeature::TranslateEnZh,
        ];
        for feature in features {
            let prompt = system_prompt(feature);
            assert!(prompt.contains("JSON"));
            assert!(prompt.contains("suggestions"));
        }
    }

    #[test]
    fn parses_http_status_and_body_without_logging_content() {
        let response = parse_http_response(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}")
            .expect("response");
        assert_eq!(response.status, 200);
        assert_eq!(response.body, b"{}");
    }
}
