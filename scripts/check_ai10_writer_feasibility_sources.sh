#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  "ai/writer_feasibility/QWEN_MODEL_NOTICE.md"
  "ai/writer_feasibility/qwen2.5-0.5b-instruct-q4-k-m.candidate.json"
  "ai/writer_feasibility/synthetic_cases.json"
  "ai/writer_feasibility/ai10_macos_arm64_report.json"
  "tools/writer_feasibility/Cargo.toml"
  "tools/writer_feasibility/src/lib.rs"
  "tools/writer_feasibility/src/main.rs"
)
for file in "${required_files[@]}"; do
  test -f "$file"
done

python3 - <<'PY'
import hashlib
import json
from pathlib import Path

candidate = json.loads(Path(
    "ai/writer_feasibility/qwen2.5-0.5b-instruct-q4-k-m.candidate.json"
).read_text())
dataset_path = Path("ai/writer_feasibility/synthetic_cases.json")
dataset = json.loads(dataset_path.read_text())
report = json.loads(Path(
    "ai/writer_feasibility/ai10_macos_arm64_report.json"
).read_text())
registry = json.loads(Path("ai/models/approved_models.json").read_text())

assert candidate["status"] == "evaluation_only"
assert candidate["owner_approved"] is False
assert candidate["redistribution_allowed"] is False
assert candidate["model"]["revision"] == "9217f5db79a29953eb74d5343926648285ec7e67"
assert candidate["model"]["sha256"] == "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
assert candidate["runtime"]["release_tag"] == "b10069"
assert candidate["runtime"]["revision"] == "178a6c44937154dc4c4eff0d166f4a044c4fceba"
assert candidate["runtime"]["archive_sha256"] == "022469e0b22f4b84dcd0a323867d7f5a31dae21894931ee6a24a35abd2a60359"
assert candidate["runtime"]["executable_sha256"] == "faa8b1c2a6c69f50b0fcec71af86eda757d34f78bbbddbb3f485f170bc586d2f"

assert dataset["provenance"] == "first_party_synthetic"
assert dataset["contains_user_data"] is False
assert len(dataset["cases"]) == 3
assert len(dataset_path.read_bytes()) == candidate["evaluation"]["dataset_size_bytes"]
assert hashlib.sha256(dataset_path.read_bytes()).hexdigest() == candidate["evaluation"]["dataset_sha256"]

assert report["stage"] == "AI-10"
assert report["candidate_id"] == candidate["model"]["id"]
assert report["model_revision"] == candidate["model"]["revision"]
assert report["runtime_release"] == candidate["runtime"]["release_tag"]
assert report["technical_passed"] is False
assert report["release_decision"] == "no_go"
assert report["cancellation"]["passed"] is True
assert sum(case["passed"] for case in report["cases"]) == 2
assert sum(not case["passed"] for case in report["cases"]) == 1
serialized_report = json.dumps(report).lower()
for forbidden in ("prompt", "output_text", "model_path", "runtime_path", "user_input"):
    assert forbidden not in serialized_report

approved_ids = {item["model_id"] for item in registry["approvals"]}
assert candidate["model"]["id"] not in approved_ids
PY

if git ls-files '*.gguf' '*.safetensors' '*.onnx' '*.ort' '*.mlmodel' '*.mlpackage/*' \
  | grep -q .; then
  echo "AI-10 evaluation weights or runtime artifacts must not be tracked." >&2
  exit 1
fi

if rg -n 'reqwest|TcpStream|UdpSocket|URLSession|NWConnection|http://|https://' \
  tools/writer_feasibility; then
  echo "AI-10 feasibility tooling must not contain a network client." >&2
  exit 1
fi

if rg -n '"--prompt"|--prompt[ =]' tools/writer_feasibility/src/main.rs; then
  echo "AI-10 must not expose an arbitrary prompt CLI." >&2
  exit 1
fi

grep -Fq \
  "Production AI-11 Writer request and output content must use the authenticated AI-09 Helper" \
  docs/privacy_spec.md
grep -Fq \
  "must never appear in process arguments, environment variables, temporary" \
  docs/privacy_spec.md
grep -Fq "native Windows peak-RSS sampler" docs/OPEN_ITEMS.md
grep -Fq "cold startup separately from warmed requests" docs/OPEN_ITEMS.md

cargo test -p private_pinyin_writer_feasibility

echo "AI-10 Writer feasibility source contract passed with a pinned No-Go report."
