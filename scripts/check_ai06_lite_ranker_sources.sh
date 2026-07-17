#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ai/eval/ai06_ranker_cases.json"
  "ai/eval/ai06_ranker_report.md"
  "ai/local_ai_core/src/lite_ranker.rs"
  "ai/models/private-pinyin-ai-lite-ranker-v1/manifest.json"
  "ai/models/private-pinyin-ai-lite-ranker-v1/model/ranker.json"
  "ai/models/private-pinyin-ai-lite-ranker-v1/MODEL_NOTICE.md"
  "tools/ai_eval_runner/src/ranker_eval.rs"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required AI-06 file: $file" >&2
    exit 1
  fi
done

git check-attr eol -- \
  ai/models/private-pinyin-ai-lite-ranker-v1/manifest.json \
  ai/models/private-pinyin-ai-lite-ranker-v1/model/ranker.json \
  ai/models/private-pinyin-ai-lite-ranker-v1/MODEL_NOTICE.md | \
  grep -c 'eol: lf' | grep -q '^3$'

grep -q 'MAX_AI_LITE_RANKER_MODEL_BYTES: u64 = 64 \* 1024' \
  ai/local_ai_core/src/lite_ranker.rs
grep -q 'MAX_CANCELLED_IDENTITIES: usize = 256' \
  ai/local_ai_core/src/lite_ranker.rs
grep -q 'AI_LITE_RANKER_VERSION: &str = "ai06-v1"' \
  ai/local_ai_core/src/lite_ranker.rs
grep -q 'AI_LITE_FEATURE_SCHEMA_VERSION: u32 = 1' \
  ai/local_ai_core/src/lite_ranker.rs
grep -q 'AiFeaturePolicy::approved_model_enabled(true)' \
  ai/local_ai_core/src/lite_ranker.rs
grep -q 'ModelRuntime::RustCompact' ai/local_ai_core/src/lite_ranker.rs
grep -q 'AiReasonCode::LiteTrigram' ai/local_ai_core/src/lite_ranker.rs
grep -q 'approved_ai06_package_improves_targets_without_regressions' \
  tools/ai_eval_runner/src/ranker_eval.rs

python3 - <<'PY'
import json
from pathlib import Path

dataset = json.loads(Path("ai/eval/ai06_ranker_cases.json").read_text())
model = json.loads(Path(
    "ai/models/private-pinyin-ai-lite-ranker-v1/model/ranker.json"
).read_text())
manifest = json.loads(Path(
    "ai/models/private-pinyin-ai-lite-ranker-v1/manifest.json"
).read_text())

assert dataset["schema_version"] == 1
assert dataset["contains_user_data"] is False
assert dataset["contains_real_application_context"] is False
assert dataset["contains_prompts_or_model_outputs"] is False
assert dataset["network_required"] is False
assert len(dataset["cases"]) == 12
assert sum(case["gate"] == "improve" for case in dataset["cases"]) == 8
assert sum(case["gate"] == "preserve" for case in dataset["cases"]) == 4

assert model["schema_version"] == 1
assert model["ranker_version"] == "ai06-v1"
assert model["feature_schema_version"] == 1
assert model["model_id"] == manifest["id"]
assert model["model_version"] == manifest["version"]
assert model["feature_scale"] == 1000
assert set(model["weights_milli"]) == {
    "base_rank", "base_score", "frequency", "segmentation",
    "bigram", "trigram", "typo_correction", "term_preservation",
}
assert all(0 <= weight <= 10_000
           for weight in model["weights_milli"].values())
assert manifest["class"] == "lite"
assert manifest["runtime"] == "rust_compact"
assert manifest["capabilities"] == ["candidate_rerank"]
assert manifest["license"]["owner_approved"] is True
assert manifest["privacy"] == {
    "runs_locally": True,
    "network_required": False,
    "stores_input": False,
}
PY

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' \
  ai/local_ai_core/src/lite_ranker.rs; then
  echo "AI-06 inference must not log candidate or model content." >&2
  exit 1
fi

bash scripts/check_no_external_ai_service.sh
cargo test -p private_pinyin_local_ai_core -p private_pinyin_ai_eval_runner
cargo run -q -p private_pinyin_ai_eval_runner -- \
  --ranker \
  --require-ranker-improvements 8

echo "AI-06 fixed-point Lite ranker gates passed."
