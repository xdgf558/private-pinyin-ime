use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const SCHEMA_VERSION: u32 = 1;
const READ_BUFFER_BYTES: usize = 64 * 1024;
const POLL_INTERVAL: Duration = Duration::from_millis(10);
const RSS_SAMPLE_INTERVAL: Duration = Duration::from_millis(25);
const MAX_CASES: usize = 32;

#[derive(Debug, Clone)]
pub struct RunPaths {
    pub candidate: PathBuf,
    pub dataset: PathBuf,
    pub model: PathBuf,
    pub runtime: PathBuf,
}

#[derive(Debug)]
pub struct ValidatedInputs {
    pub candidate: CandidateSpec,
    pub dataset: EvaluationDataset,
}

#[derive(Debug)]
pub struct ProbeError {
    code: &'static str,
}

impl ProbeError {
    pub const fn argument(code: &'static str) -> Self {
        Self { code }
    }

    pub const fn code(&self) -> &'static str {
        self.code
    }
}

impl std::fmt::Display for ProbeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.code)
    }
}

impl std::error::Error for ProbeError {}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CandidateSpec {
    pub schema_version: u32,
    pub status: CandidateStatus,
    pub owner_approved: bool,
    pub redistribution_allowed: bool,
    pub model: ModelSource,
    pub runtime: RuntimeSource,
    pub evaluation: EvaluationPolicy,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CandidateStatus {
    EvaluationOnly,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelSource {
    pub id: String,
    pub repository: String,
    pub revision: String,
    pub file: String,
    pub download_url: String,
    pub size_bytes: u64,
    pub sha256: String,
    pub license: String,
    pub license_url: String,
    pub quantization: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RuntimeSource {
    pub name: String,
    pub repository: String,
    pub release_tag: String,
    pub revision: String,
    pub archive_file: String,
    pub archive_url: String,
    pub archive_size_bytes: u64,
    pub archive_sha256: String,
    pub executable_file: String,
    pub executable_sha256: String,
    pub version_contains: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EvaluationPolicy {
    pub dataset_file: String,
    pub dataset_size_bytes: u64,
    pub dataset_sha256: String,
    pub max_prompt_bytes: usize,
    pub max_output_bytes: usize,
    pub max_peak_rss_mb: u64,
    pub short_completion_first_byte_ms: u64,
    pub rewrite_total_ms: u64,
    pub cancellation_probe_timeout_ms: u64,
    pub cancellation_budget_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EvaluationDataset {
    pub schema_version: u32,
    pub provenance: DatasetProvenance,
    pub contains_user_data: bool,
    pub cases: Vec<EvaluationCase>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DatasetProvenance {
    FirstPartySynthetic,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EvaluationCase {
    pub id: String,
    pub feature: EvaluationFeature,
    pub prompt: String,
    pub max_tokens: u32,
    pub timeout_ms: u64,
    pub required_any: Vec<String>,
    pub forbidden_any: Vec<String>,
    pub max_output_chars: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvaluationFeature {
    ShortCompletion,
    Rewrite,
    Translation,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReleaseDecision {
    NoGo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FeasibilityReport {
    pub schema_version: u32,
    pub stage: String,
    pub generated_unix_seconds: u64,
    pub candidate_id: String,
    pub model_revision: String,
    pub runtime_release: String,
    pub platform: String,
    pub architecture: String,
    pub latency_scope: String,
    pub warm_request_evidence: bool,
    pub native_windows_rss_evidence: bool,
    pub technical_passed: bool,
    pub release_decision: ReleaseDecision,
    pub decision_reasons: Vec<DecisionReason>,
    pub cancellation: CancellationResult,
    pub cases: Vec<CaseResult>,
}

impl FeasibilityReport {
    pub fn write_json(&self, path: &Path) -> Result<(), ProbeError> {
        let mut bytes = serde_json::to_vec_pretty(self).map_err(|_| error("report_encode"))?;
        bytes.push(b'\n');
        write_private_file(path, &bytes)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DecisionReason {
    CandidateNotOwnerApproved,
    RedistributionNotApproved,
    TechnicalGateFailed,
    WarmLatencyEvidenceMissing,
    WindowsMemoryEvidenceMissing,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CancellationResult {
    pub passed: bool,
    pub result_code: ResultCode,
    pub cancellation_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CaseResult {
    pub id: String,
    pub feature: EvaluationFeature,
    pub passed: bool,
    pub result_code: ResultCode,
    pub first_byte_ms: Option<u64>,
    pub total_ms: u64,
    pub peak_rss_mb: Option<u64>,
    pub output_chars: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResultCode {
    Passed,
    TimedOut,
    Cancelled,
    RuntimeFailed,
    OutputTooLarge,
    OutputEmpty,
    OutputTooLong,
    RequiredTextMissing,
    ForbiddenTextPresent,
    LatencyBudgetExceeded,
    MemoryBudgetExceeded,
}

pub fn validate_inputs(paths: &RunPaths) -> Result<ValidatedInputs, ProbeError> {
    let candidate_bytes = read_bounded_file(&paths.candidate, 64 * 1024)?;
    let candidate: CandidateSpec =
        serde_json::from_slice(&candidate_bytes).map_err(|_| error("candidate_invalid"))?;
    validate_candidate(&candidate)?;

    let dataset_bytes = read_bounded_file(&paths.dataset, 256 * 1024)?;
    if paths.dataset.file_name().and_then(|name| name.to_str())
        != Some(candidate.evaluation.dataset_file.as_str())
        || dataset_bytes.len() as u64 != candidate.evaluation.dataset_size_bytes
        || sha256_bytes(&dataset_bytes) != candidate.evaluation.dataset_sha256
    {
        return Err(error("dataset_integrity_mismatch"));
    }
    let dataset: EvaluationDataset =
        serde_json::from_slice(&dataset_bytes).map_err(|_| error("dataset_invalid"))?;
    validate_dataset(&dataset, &candidate.evaluation)?;

    verify_file(
        &paths.model,
        candidate.model.size_bytes,
        &candidate.model.sha256,
    )?;
    verify_file_hash(&paths.runtime, &candidate.runtime.executable_sha256)?;
    validate_runtime_version(&paths.runtime, &candidate.runtime.version_contains)?;

    Ok(ValidatedInputs { candidate, dataset })
}

pub fn run_feasibility(paths: &RunPaths) -> Result<FeasibilityReport, ProbeError> {
    let validated = validate_inputs(paths)?;
    let mut case_results = Vec::with_capacity(validated.dataset.cases.len());
    for case in &validated.dataset.cases {
        case_results.push(run_case(
            &paths.runtime,
            &paths.model,
            case,
            &validated.candidate.evaluation,
        )?);
    }

    let cancellation = run_cancellation_probe(
        &paths.runtime,
        &paths.model,
        &validated.dataset.cases[0],
        &validated.candidate.evaluation,
    )?;
    let technical_passed = case_results.iter().all(|result| result.passed) && cancellation.passed;
    let mut decision_reasons = vec![
        DecisionReason::CandidateNotOwnerApproved,
        DecisionReason::RedistributionNotApproved,
        DecisionReason::WarmLatencyEvidenceMissing,
        DecisionReason::WindowsMemoryEvidenceMissing,
    ];
    if !technical_passed {
        decision_reasons.push(DecisionReason::TechnicalGateFailed);
    }

    Ok(FeasibilityReport {
        schema_version: SCHEMA_VERSION,
        stage: candidate_stage(&validated.candidate).to_owned(),
        generated_unix_seconds: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
        candidate_id: validated.candidate.model.id,
        model_revision: validated.candidate.model.revision,
        runtime_release: validated.candidate.runtime.release_tag,
        platform: std::env::consts::OS.to_owned(),
        architecture: std::env::consts::ARCH.to_owned(),
        latency_scope: "cold_process_start".to_owned(),
        warm_request_evidence: false,
        native_windows_rss_evidence: false,
        technical_passed,
        release_decision: ReleaseDecision::NoGo,
        decision_reasons,
        cancellation,
        cases: case_results,
    })
}

fn validate_candidate(candidate: &CandidateSpec) -> Result<(), ProbeError> {
    let evaluation = &candidate.evaluation;
    if candidate.schema_version != SCHEMA_VERSION
        || candidate.status != CandidateStatus::EvaluationOnly
        || candidate.owner_approved
        || candidate.redistribution_allowed
        || !is_exact_model_candidate(&candidate.model)
        || !is_exact_runtime_candidate(&candidate.runtime)
        || !is_lower_sha256(&candidate.model.sha256)
        || !is_lower_sha256(&candidate.runtime.archive_sha256)
        || !is_lower_sha256(&candidate.runtime.executable_sha256)
        || !is_lower_sha256(&evaluation.dataset_sha256)
        || !is_https_url(&candidate.model.download_url)
        || !is_https_url(&candidate.model.license_url)
        || !is_https_url(&candidate.runtime.archive_url)
        || evaluation.max_prompt_bytes == 0
        || evaluation.max_prompt_bytes > 4096
        || evaluation.max_output_bytes == 0
        || evaluation.max_output_bytes > 16 * 1024
        || evaluation.max_peak_rss_mb == 0
        || evaluation.max_peak_rss_mb > 2048
        || evaluation.short_completion_first_byte_ms == 0
        || evaluation.rewrite_total_ms == 0
        || evaluation.cancellation_probe_timeout_ms == 0
        || evaluation.cancellation_budget_ms == 0
    {
        return Err(error("candidate_policy_rejected"));
    }
    Ok(())
}

fn candidate_stage(candidate: &CandidateSpec) -> &'static str {
    if candidate.model.id == "qwen2.5-1.5b-instruct-q4-k-m" {
        "AI-11"
    } else {
        "AI-10"
    }
}

fn is_exact_model_candidate(model: &ModelSource) -> bool {
    let common = model.license == "Apache-2.0"
        && model.license_url == "https://www.apache.org/licenses/LICENSE-2.0"
        && model.quantization == "Q4_K_M";
    common
        && (matches_exact_model(
            model,
            "qwen2.5-0.5b-instruct-q4-k-m",
            "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
            "9217f5db79a29953eb74d5343926648285ec7e67",
            "qwen2.5-0.5b-instruct-q4_k_m.gguf",
            491_400_032,
            "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db",
        ) || matches_exact_model(
            model,
            "qwen2.5-1.5b-instruct-q4-k-m",
            "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
            "dd26da440ef0330c47919d1ecae0966d24022222",
            "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            1_117_320_736,
            "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
        ))
}

fn matches_exact_model(
    model: &ModelSource,
    id: &str,
    repository: &str,
    revision: &str,
    file: &str,
    size_bytes: u64,
    sha256: &str,
) -> bool {
    model.id == id
        && model.repository == repository
        && model.revision == revision
        && model.file == file
        && model.size_bytes == size_bytes
        && model.sha256 == sha256
        && model.download_url
            == format!("https://huggingface.co/{repository}/resolve/{revision}/{file}")
}

fn is_exact_runtime_candidate(runtime: &RuntimeSource) -> bool {
    runtime.name == "llama.cpp"
        && runtime.repository == "ggml-org/llama.cpp"
        && runtime.release_tag == "b10069"
        && runtime.revision == "178a6c44937154dc4c4eff0d166f4a044c4fceba"
        && runtime.archive_file == "llama-b10069-bin-macos-arm64.tar.gz"
        && runtime.archive_url
            == "https://github.com/ggml-org/llama.cpp/releases/download/b10069/llama-b10069-bin-macos-arm64.tar.gz"
        && runtime.archive_size_bytes == 10_600_037
        && runtime.archive_sha256
            == "022469e0b22f4b84dcd0a323867d7f5a31dae21894931ee6a24a35abd2a60359"
        && runtime.executable_file == "llama-completion"
        && runtime.executable_sha256
            == "faa8b1c2a6c69f50b0fcec71af86eda757d34f78bbbddbb3f485f170bc586d2f"
        && runtime.version_contains
            == ["version: 10069".to_owned(), "178a6c449".to_owned()]
}

fn validate_dataset(
    dataset: &EvaluationDataset,
    policy: &EvaluationPolicy,
) -> Result<(), ProbeError> {
    let requires_translation = policy.dataset_file == "ai11_synthetic_cases.json";
    if dataset.schema_version != SCHEMA_VERSION
        || dataset.provenance != DatasetProvenance::FirstPartySynthetic
        || dataset.contains_user_data
        || dataset.cases.is_empty()
        || dataset.cases.len() > MAX_CASES
        || !dataset
            .cases
            .iter()
            .any(|case| case.feature == EvaluationFeature::ShortCompletion)
        || !dataset
            .cases
            .iter()
            .any(|case| case.feature == EvaluationFeature::Rewrite)
        || (requires_translation
            && !dataset
                .cases
                .iter()
                .any(|case| case.feature == EvaluationFeature::Translation))
    {
        return Err(error("dataset_policy_rejected"));
    }

    for case in &dataset.cases {
        if !is_safe_identifier(&case.id)
            || case.prompt.is_empty()
            || case.prompt.len() > policy.max_prompt_bytes
            || case.prompt.chars().any(char::is_control)
            || case.max_tokens == 0
            || case.max_tokens > 128
            || case.timeout_ms == 0
            || case.timeout_ms > 10_000
            || case.max_output_chars == 0
            || case.max_output_chars > 1024
            || case.required_any.len() > 16
            || case.forbidden_any.len() > 16
            || case
                .required_any
                .iter()
                .chain(&case.forbidden_any)
                .any(|text| text.is_empty() || text.chars().count() > 64)
        {
            return Err(error("dataset_case_rejected"));
        }
    }
    Ok(())
}

fn validate_runtime_version(runtime: &Path, required: &[String]) -> Result<(), ProbeError> {
    let output = Command::new(runtime)
        .arg("--version")
        .stdin(Stdio::null())
        .output()
        .map_err(|_| error("runtime_launch_failed"))?;
    if !output.status.success() {
        return Err(error("runtime_version_failed"));
    }
    let mut version = output.stdout;
    version.extend_from_slice(&output.stderr);
    let version = String::from_utf8_lossy(&version);
    if required.iter().any(|token| !version.contains(token)) {
        return Err(error("runtime_version_mismatch"));
    }
    Ok(())
}

fn run_case(
    runtime: &Path,
    model: &Path,
    case: &EvaluationCase,
    policy: &EvaluationPolicy,
) -> Result<CaseResult, ProbeError> {
    let prompt = chatml_prompt(&case.prompt);
    let process = run_llama_process(
        runtime,
        model,
        &prompt,
        case.max_tokens,
        Duration::from_millis(case.timeout_ms),
        policy.max_output_bytes,
    )?;
    let mut result_code = process.result_code;
    let output = String::from_utf8_lossy(&process.output);
    let normalized = normalize_output(&output);
    let output_chars = normalized.chars().count();
    if result_code == ResultCode::Passed && normalized.is_empty() {
        result_code = ResultCode::OutputEmpty;
    } else if result_code == ResultCode::Passed && output_chars > case.max_output_chars {
        result_code = ResultCode::OutputTooLong;
    } else if result_code == ResultCode::Passed
        && !case.required_any.is_empty()
        && !case
            .required_any
            .iter()
            .any(|text| normalized.contains(text))
    {
        result_code = ResultCode::RequiredTextMissing;
    } else if result_code == ResultCode::Passed
        && case
            .forbidden_any
            .iter()
            .any(|text| normalized.contains(text))
    {
        result_code = ResultCode::ForbiddenTextPresent;
    } else if result_code == ResultCode::Passed
        && ((case.feature == EvaluationFeature::ShortCompletion
            && process.first_byte.is_none_or(|latency| {
                latency.as_millis() as u64 > policy.short_completion_first_byte_ms
            }))
            || (matches!(
                case.feature,
                EvaluationFeature::Rewrite | EvaluationFeature::Translation
            ) && process.total.as_millis() as u64 > policy.rewrite_total_ms))
    {
        result_code = ResultCode::LatencyBudgetExceeded;
    } else if result_code == ResultCode::Passed
        && process
            .peak_rss_kb
            .is_some_and(|rss| rss / 1024 > policy.max_peak_rss_mb)
    {
        result_code = ResultCode::MemoryBudgetExceeded;
    }

    Ok(CaseResult {
        id: case.id.clone(),
        feature: case.feature,
        passed: result_code == ResultCode::Passed,
        result_code,
        first_byte_ms: process
            .first_byte
            .map(|duration| duration.as_millis() as u64),
        total_ms: process.total.as_millis() as u64,
        peak_rss_mb: process.peak_rss_kb.map(|rss| rss / 1024),
        output_chars,
    })
}

fn run_cancellation_probe(
    runtime: &Path,
    model: &Path,
    source_case: &EvaluationCase,
    policy: &EvaluationPolicy,
) -> Result<CancellationResult, ProbeError> {
    let prompt = chatml_prompt(&source_case.prompt);
    let process = run_llama_process(
        runtime,
        model,
        &prompt,
        128,
        Duration::from_millis(policy.cancellation_probe_timeout_ms),
        policy.max_output_bytes,
    )?;
    let passed = process.result_code == ResultCode::TimedOut
        && process.cancellation <= Duration::from_millis(policy.cancellation_budget_ms);
    Ok(CancellationResult {
        passed,
        result_code: if passed {
            ResultCode::Cancelled
        } else {
            process.result_code
        },
        cancellation_ms: process.cancellation.as_millis() as u64,
    })
}

fn chatml_prompt(prompt: &str) -> String {
    format!(
        "<|im_start|>system\n你是本地中文写作助手。严格按用户要求只输出结果，不解释。<|im_end|>\n<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n"
    )
}

fn normalize_output(output: &str) -> String {
    output
        .replace("<|im_end|>", "")
        .replace("<|im_start|>", "")
        .replace("[end of text]", "")
        .trim()
        .to_owned()
}

struct ProcessResult {
    result_code: ResultCode,
    output: Vec<u8>,
    first_byte: Option<Duration>,
    total: Duration,
    peak_rss_kb: Option<u64>,
    cancellation: Duration,
}

fn run_llama_process(
    runtime: &Path,
    model: &Path,
    prompt: &str,
    max_tokens: u32,
    timeout: Duration,
    max_output_bytes: usize,
) -> Result<ProcessResult, ProbeError> {
    let mut child = Command::new(runtime)
        .arg("--model")
        .arg(model)
        .arg("--prompt")
        .arg(prompt)
        .arg("--n-predict")
        .arg(max_tokens.to_string())
        .arg("--ctx-size")
        .arg("1024")
        .arg("--temp")
        .arg("0")
        .arg("--seed")
        .arg("1")
        .arg("--no-display-prompt")
        .arg("--simple-io")
        .arg("--offline")
        .arg("--log-verbosity")
        .arg("1")
        .arg("--no-conversation")
        .arg("--gpu-layers")
        .arg("99")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| error("runtime_launch_failed"))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| error("runtime_pipe_failed"))?;
    let receiver = spawn_reader(stdout);
    monitor_child(
        &mut child,
        receiver,
        timeout,
        max_output_bytes,
        Instant::now(),
    )
}

enum ReaderMessage {
    Chunk(Vec<u8>, Instant),
    Finished,
    Failed,
}

fn spawn_reader(mut stdout: impl Read + Send + 'static) -> Receiver<ReaderMessage> {
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut buffer = [0_u8; 1024];
        loop {
            match stdout.read(&mut buffer) {
                Ok(0) => {
                    let _ = sender.send(ReaderMessage::Finished);
                    break;
                }
                Ok(read) => {
                    if sender
                        .send(ReaderMessage::Chunk(
                            buffer[..read].to_vec(),
                            Instant::now(),
                        ))
                        .is_err()
                    {
                        break;
                    }
                }
                Err(_) => {
                    let _ = sender.send(ReaderMessage::Failed);
                    break;
                }
            }
        }
    });
    receiver
}

fn monitor_child(
    child: &mut Child,
    receiver: Receiver<ReaderMessage>,
    timeout: Duration,
    max_output_bytes: usize,
    started: Instant,
) -> Result<ProcessResult, ProbeError> {
    let mut output = Vec::new();
    let mut first_byte = None;
    let mut peak_rss_kb = None;
    let mut next_rss_sample = started;
    loop {
        loop {
            match receiver.try_recv() {
                Ok(ReaderMessage::Chunk(chunk, at)) => {
                    if first_byte.is_none() && chunk.iter().any(|byte| !byte.is_ascii_whitespace())
                    {
                        first_byte = Some(at.saturating_duration_since(started));
                    }
                    if output.len().saturating_add(chunk.len()) > max_output_bytes {
                        terminate_child(child)?;
                        return Ok(ProcessResult {
                            result_code: ResultCode::OutputTooLarge,
                            output: Vec::new(),
                            first_byte,
                            total: started.elapsed(),
                            peak_rss_kb,
                            cancellation: Duration::ZERO,
                        });
                    }
                    output.extend_from_slice(&chunk);
                }
                Ok(ReaderMessage::Finished) => {}
                Ok(ReaderMessage::Failed) => return Err(error("runtime_output_failed")),
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    break;
                }
            }
        }

        let now = Instant::now();
        if now >= next_rss_sample {
            if let Some(rss) = sample_rss_kb(child.id()) {
                peak_rss_kb = Some(peak_rss_kb.unwrap_or_default().max(rss));
            }
            next_rss_sample = now + RSS_SAMPLE_INTERVAL;
        }

        if started.elapsed() >= timeout {
            let cancellation_started = Instant::now();
            terminate_child(child)?;
            return Ok(ProcessResult {
                result_code: ResultCode::TimedOut,
                output: Vec::new(),
                first_byte,
                total: started.elapsed(),
                peak_rss_kb,
                cancellation: cancellation_started.elapsed(),
            });
        }

        if let Some(status) = child.try_wait().map_err(|_| error("runtime_wait_failed"))? {
            drain_reader(
                &receiver,
                &mut output,
                max_output_bytes,
                &mut first_byte,
                started,
            )?;
            return Ok(ProcessResult {
                result_code: if status.success() {
                    ResultCode::Passed
                } else {
                    ResultCode::RuntimeFailed
                },
                output,
                first_byte,
                total: started.elapsed(),
                peak_rss_kb,
                cancellation: Duration::ZERO,
            });
        }
        thread::sleep(POLL_INTERVAL);
    }
}

fn drain_reader(
    receiver: &Receiver<ReaderMessage>,
    output: &mut Vec<u8>,
    max_output_bytes: usize,
    first_byte: &mut Option<Duration>,
    started: Instant,
) -> Result<(), ProbeError> {
    let deadline = Instant::now() + Duration::from_millis(100);
    while Instant::now() < deadline {
        match receiver.recv_timeout(Duration::from_millis(5)) {
            Ok(ReaderMessage::Chunk(chunk, at)) => {
                if first_byte.is_none() && chunk.iter().any(|byte| !byte.is_ascii_whitespace()) {
                    *first_byte = Some(at.saturating_duration_since(started));
                }
                if output.len().saturating_add(chunk.len()) > max_output_bytes {
                    return Err(error("runtime_output_too_large"));
                }
                output.extend_from_slice(&chunk);
            }
            Ok(ReaderMessage::Finished) | Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Ok(ReaderMessage::Failed) => return Err(error("runtime_output_failed")),
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }
    }
    Ok(())
}

fn terminate_child(child: &mut Child) -> Result<(), ProbeError> {
    match child.try_wait().map_err(|_| error("runtime_wait_failed"))? {
        Some(_) => Ok(()),
        None => {
            child.kill().map_err(|_| error("runtime_cancel_failed"))?;
            child.wait().map_err(|_| error("runtime_wait_failed"))?;
            Ok(())
        }
    }
}

fn sample_rss_kb(pid: u32) -> Option<u64> {
    if !matches!(std::env::consts::OS, "macos" | "linux") {
        return None;
    }
    let output = Command::new("ps")
        .args(["-o", "rss=", "-p", &pid.to_string()])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    String::from_utf8(output.stdout)
        .ok()?
        .trim()
        .parse::<u64>()
        .ok()
}

fn verify_file(path: &Path, expected_size: u64, expected_sha256: &str) -> Result<(), ProbeError> {
    let metadata = regular_file_metadata(path)?;
    if metadata.len() != expected_size {
        return Err(error("model_size_mismatch"));
    }
    verify_file_hash(path, expected_sha256)
}

fn verify_file_hash(path: &Path, expected_sha256: &str) -> Result<(), ProbeError> {
    regular_file_metadata(path)?;
    let mut file = fs::File::open(path).map_err(|_| error("artifact_open_failed"))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; READ_BUFFER_BYTES];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|_| error("artifact_read_failed"))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    if encode_lower_hex(&hasher.finalize()) != expected_sha256 {
        return Err(error("artifact_hash_mismatch"));
    }
    Ok(())
}

fn regular_file_metadata(path: &Path) -> Result<fs::Metadata, ProbeError> {
    let metadata = fs::symlink_metadata(path).map_err(|_| error("artifact_not_found"))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(error("artifact_type_rejected"));
    }
    Ok(metadata)
}

fn read_bounded_file(path: &Path, maximum: u64) -> Result<Vec<u8>, ProbeError> {
    let metadata = regular_file_metadata(path)?;
    if metadata.len() > maximum {
        return Err(error("metadata_too_large"));
    }
    fs::read(path).map_err(|_| error("metadata_read_failed"))
}

fn write_private_file(path: &Path, bytes: &[u8]) -> Result<(), ProbeError> {
    let parent = path
        .parent()
        .ok_or_else(|| error("report_parent_missing"))?;
    fs::create_dir_all(parent).map_err(|_| error("report_directory_failed"))?;
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(path)
        .map_err(|_| error("report_open_failed"))?;
    file.write_all(bytes)
        .map_err(|_| error("report_write_failed"))?;
    file.sync_all().map_err(|_| error("report_sync_failed"))
}

fn sha256_bytes(bytes: &[u8]) -> String {
    encode_lower_hex(&Sha256::digest(bytes))
}

fn encode_lower_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

fn is_lower_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn is_https_url(value: &str) -> bool {
    value.starts_with(concat!("https", "://"))
        && !value.chars().any(|character| character.is_whitespace())
}

fn is_safe_identifier(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

const fn error(code: &'static str) -> ProbeError {
    ProbeError { code }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PINNED_CANDIDATE: &str =
        include_str!("../../../ai/writer_feasibility/qwen2.5-0.5b-instruct-q4-k-m.candidate.json");
    const AI11_CANDIDATE: &str =
        include_str!("../../../ai/writer_feasibility/qwen2.5-1.5b-instruct-q4-k-m.candidate.json");
    const SYNTHETIC_CASES: &str =
        include_str!("../../../ai/writer_feasibility/synthetic_cases.json");
    const AI11_SYNTHETIC_CASES: &str =
        include_str!("../../../ai/writer_feasibility/ai11_synthetic_cases.json");

    #[test]
    fn pinned_candidate_remains_evaluation_only_and_synthetic() {
        let candidate: CandidateSpec = serde_json::from_str(PINNED_CANDIDATE).unwrap();
        let dataset: EvaluationDataset = serde_json::from_str(SYNTHETIC_CASES).unwrap();

        validate_candidate(&candidate).unwrap();
        validate_dataset(&dataset, &candidate.evaluation).unwrap();
        assert_eq!(candidate.status, CandidateStatus::EvaluationOnly);
        assert!(!candidate.owner_approved);
        assert!(!candidate.redistribution_allowed);
        assert_eq!(
            candidate.model.revision,
            "9217f5db79a29953eb74d5343926648285ec7e67"
        );
        assert_eq!(candidate.runtime.release_tag, "b10069");
        assert_eq!(dataset.provenance, DatasetProvenance::FirstPartySynthetic);
        assert!(!dataset.contains_user_data);
        assert_eq!(dataset.cases.len(), 3);
    }

    #[test]
    fn candidate_self_approval_is_rejected() {
        let mut candidate: CandidateSpec = serde_json::from_str(PINNED_CANDIDATE).unwrap();
        candidate.owner_approved = true;
        assert_eq!(
            validate_candidate(&candidate).unwrap_err().code(),
            "candidate_policy_rejected"
        );
    }

    #[test]
    fn ai11_candidate_is_exact_unapproved_and_covers_all_writer_features() {
        let candidate: CandidateSpec = serde_json::from_str(AI11_CANDIDATE).unwrap();
        let dataset: EvaluationDataset = serde_json::from_str(AI11_SYNTHETIC_CASES).unwrap();

        validate_candidate(&candidate).unwrap();
        validate_dataset(&dataset, &candidate.evaluation).unwrap();
        assert_eq!(candidate_stage(&candidate), "AI-11");
        assert_eq!(
            candidate.model.revision,
            "dd26da440ef0330c47919d1ecae0966d24022222"
        );
        assert_eq!(
            candidate.model.sha256,
            "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
        );
        assert!(!candidate.owner_approved);
        assert!(!candidate.redistribution_allowed);
        assert!(dataset
            .cases
            .iter()
            .any(|case| case.feature == EvaluationFeature::ShortCompletion));
        assert!(dataset
            .cases
            .iter()
            .any(|case| case.feature == EvaluationFeature::Rewrite));
        assert!(dataset
            .cases
            .iter()
            .any(|case| case.feature == EvaluationFeature::Translation));
    }

    #[test]
    fn ai11_candidate_identity_cannot_be_repointed() {
        let mut candidate: CandidateSpec = serde_json::from_str(AI11_CANDIDATE).unwrap();
        candidate.model.revision = "main".to_owned();
        assert_eq!(
            validate_candidate(&candidate).unwrap_err().code(),
            "candidate_policy_rejected"
        );
    }

    #[test]
    fn report_schema_contains_no_prompt_or_output_fields() {
        let report = FeasibilityReport {
            schema_version: 1,
            stage: "AI-10".to_owned(),
            generated_unix_seconds: 0,
            candidate_id: "candidate".to_owned(),
            model_revision: "revision".to_owned(),
            runtime_release: "runtime".to_owned(),
            platform: "test".to_owned(),
            architecture: "test".to_owned(),
            latency_scope: "cold_process_start".to_owned(),
            warm_request_evidence: false,
            native_windows_rss_evidence: false,
            technical_passed: false,
            release_decision: ReleaseDecision::NoGo,
            decision_reasons: vec![DecisionReason::CandidateNotOwnerApproved],
            cancellation: CancellationResult {
                passed: true,
                result_code: ResultCode::Cancelled,
                cancellation_ms: 1,
            },
            cases: vec![CaseResult {
                id: "synthetic".to_owned(),
                feature: EvaluationFeature::Rewrite,
                passed: true,
                result_code: ResultCode::Passed,
                first_byte_ms: Some(1),
                total_ms: 2,
                peak_rss_mb: Some(3),
                output_chars: 4,
            }],
        };
        let json = serde_json::to_string(&report).unwrap();
        assert!(!json.contains("prompt"));
        assert!(!json.contains("output_text"));
        assert!(!json.contains("model_path"));
        assert!(!json.contains("runtime_path"));
        assert!(json.contains("cold_process_start"));
        assert!(json.contains("warm_request_evidence"));
        assert!(json.contains("native_windows_rss_evidence"));
    }

    #[test]
    fn output_quality_is_checked_without_persisting_content() {
        let case = EvaluationCase {
            id: "quality".to_owned(),
            feature: EvaluationFeature::Rewrite,
            prompt: "synthetic".to_owned(),
            max_tokens: 16,
            timeout_ms: 1000,
            required_any: vec!["请".to_owned()],
            forbidden_any: vec!["解释".to_owned()],
            max_output_chars: 32,
        };
        assert!(normalize_output("请按时到达").contains(&case.required_any[0]));
        assert!(case
            .forbidden_any
            .iter()
            .any(|text| normalize_output("解释：请按时到达").contains(text)));
        assert_eq!(normalize_output("请按时到达 [end of text]"), "请按时到达");
    }

    #[test]
    fn chat_template_uses_bounded_synthetic_prompt_verbatim() {
        let prompt = chatml_prompt("请改写这句合成文本");
        assert!(prompt.contains("请改写这句合成文本"));
        assert!(prompt.ends_with("<|im_start|>assistant\n"));
    }
}
