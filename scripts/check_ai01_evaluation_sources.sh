#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ai/README.md"
  "ai/eval/README.md"
  "ai/eval/baseline_cases.tsv"
  "ai/eval/dataset_manifest.json"
  "docs/local_ai_development_plan.md"
  "tools/ai_eval_runner/Cargo.toml"
  "tools/ai_eval_runner/src/lib.rs"
  "tools/ai_benchmark/Cargo.toml"
  "tools/ai_benchmark/src/main.rs"
  "scripts/run_ai_eval.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required AI-01 file: $file" >&2
    exit 1
  fi
done

grep -q 'tools/ai_eval_runner' Cargo.toml
grep -q 'tools/ai_benchmark' Cargo.toml
grep -q '"case_count": 20' ai/eval/dataset_manifest.json
grep -q '"contains_user_data": false' ai/eval/dataset_manifest.json
grep -q '"contains_real_application_context": false' ai/eval/dataset_manifest.json
grep -q 'project_regression or synthetic' tools/ai_eval_runner/src/lib.rs
grep -q 'Candidate stability rule' docs/local_ai_development_plan.md

case_count="$(awk -F '\t' 'NR > 1 && $0 !~ /^#/ && NF { count += 1 } END { print count + 0 }' ai/eval/baseline_cases.tsv)"
if [[ "$case_count" != "20" ]]; then
  echo "AI-01 manifest expects 20 cases but dataset contains $case_count" >&2
  exit 1
fi

bash scripts/run_ai_eval.sh

echo "AI-01 evaluation source checks passed."
