#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  "ai/writer_feasibility/QWEN_1_5B_MODEL_NOTICE.md"
  "ai/writer_feasibility/qwen2.5-1.5b-instruct-q4-k-m.candidate.json"
  "ai/writer_feasibility/ai11_synthetic_cases.json"
  "ai/writer_feasibility/ai11_macos_arm64_report.json"
  "ai/helper_protocol/src/lib.rs"
  "ai/helper/private_pinyin_ai_helper/src/main.rs"
)
for file in "${required_files[@]}"; do
  test -f "$file"
done

python3 - <<'PY'
import hashlib
import json
from pathlib import Path

candidate = json.loads(Path(
    "ai/writer_feasibility/qwen2.5-1.5b-instruct-q4-k-m.candidate.json"
).read_text())
dataset_path = Path("ai/writer_feasibility/ai11_synthetic_cases.json")
dataset = json.loads(dataset_path.read_text())
report = json.loads(Path(
    "ai/writer_feasibility/ai11_macos_arm64_report.json"
).read_text())
settings = json.loads(Path("config/default_settings.json").read_text())
registry = json.loads(Path("ai/models/approved_models.json").read_text())

assert candidate["status"] == "evaluation_only"
assert candidate["owner_approved"] is False
assert candidate["redistribution_allowed"] is False
assert candidate["model"]["revision"] == "dd26da440ef0330c47919d1ecae0966d24022222"
assert candidate["model"]["size_bytes"] == 1117320736
assert candidate["model"]["sha256"] == "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
assert candidate["runtime"]["release_tag"] == "b10069"
assert candidate["runtime"]["executable_sha256"] == "faa8b1c2a6c69f50b0fcec71af86eda757d34f78bbbddbb3f485f170bc586d2f"

assert dataset["provenance"] == "first_party_synthetic"
assert dataset["contains_user_data"] is False
assert {case["feature"] for case in dataset["cases"]} == {
    "short_completion", "rewrite", "translation"
}
assert len(dataset_path.read_bytes()) == candidate["evaluation"]["dataset_size_bytes"]
assert hashlib.sha256(dataset_path.read_bytes()).hexdigest() == candidate["evaluation"]["dataset_sha256"]

assert report["stage"] == "AI-11"
assert report["candidate_id"] == candidate["model"]["id"]
assert report["model_revision"] == candidate["model"]["revision"]
assert report["latency_scope"] == "cold_process_start"
assert report["warm_request_evidence"] is False
assert report["native_windows_rss_evidence"] is False
assert report["technical_passed"] is True
assert report["release_decision"] == "no_go"
assert all(case["passed"] for case in report["cases"])
assert report["cancellation"]["passed"] is True
assert "candidate_not_owner_approved" in report["decision_reasons"]
assert "redistribution_not_approved" in report["decision_reasons"]
assert "warm_latency_evidence_missing" in report["decision_reasons"]
assert "windows_memory_evidence_missing" in report["decision_reasons"]
serialized_report = json.dumps(report).lower()
for forbidden in ("prompt", "output_text", "model_path", "runtime_path", "user_input"):
    assert forbidden not in serialized_report

ai = settings["ai"]
assert ai["enable_short_completion"] is False
assert ai["enable_rewrite"] is False
assert ai["enable_translation"] is False
assert ai["ai_writer_max_memory_mb"] == 2048
assert ai["ai_writer_idle_unload_seconds"] == 600
assert ai["ai_timeout_completion_ms"] == 800
assert ai["ai_timeout_rewrite_ms"] == 3000
assert ai["disable_ai_on_battery_saver"] is True

approved_ids = {item["model_id"] for item in registry["approvals"]}
assert candidate["model"]["id"] not in approved_ids
PY

if git ls-files '*.gguf' '*.safetensors' '*.onnx' '*.ort' '*.mlmodel' '*.mlpackage/*' \
  | grep -q .; then
  echo "AI-11 model weights or runtime artifacts must not be tracked." >&2
  exit 1
fi

grep -Fq "WriterInference = 6" ai/helper_protocol/src/lib.rs
grep -Fq "WriterCompleted = 0x8006" ai/helper_protocol/src/lib.rs
grep -Fq "ModelUnavailable = 8" ai/helper_protocol/src/lib.rs
grep -Fq "MAX_WRITER_SUGGESTIONS: usize = 3" ai/helper_protocol/src/lib.rs
grep -Fq "HelperErrorCode::ModelUnavailable" ai/helper/private_pinyin_ai_helper/src/main.rs
grep -Fq 'source", &"<redacted>"' ai/helper_protocol/src/lib.rs
grep -Fq 'suggestions", &"<redacted>"' ai/helper_protocol/src/lib.rs

if rg -n 'reqwest|TcpStream|UdpSocket|URLSession|NWConnection|http://|https://' \
  ai/helper_protocol ai/helper/private_pinyin_ai_helper; then
  echo "AI-11 Helper path must not contain a network client." >&2
  exit 1
fi

grep -Fq "Writer remains unavailable until every model and platform gate passes" \
  docs/privacy_spec.md
grep -Fq "native Windows RSS and warmed-request evidence" docs/OPEN_ITEMS.md
grep -Fq "停顿时当前输入会交给本地 AI 进程" docs/OPEN_ITEMS.md
grep -Fq "privacy always disables all three content-bearing Writer features" \
  docs/privacy_spec.md
grep -Fq "strict_privacy_disables_writer_content_features_but_preserves_lite_policy" \
  ime_core/tests/settings_tests.rs

cargo test -p private_pinyin_ai_helper_protocol
cargo test -p private_pinyin_ai_helper
cargo test -p private_pinyin_writer_feasibility

echo "AI-11 Writer contracts and content-free No-Go evidence passed."
