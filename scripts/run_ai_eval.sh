#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--benchmark" ]]; then
  shift
  cargo run --release -q -p private_pinyin_ai_benchmark -- "$@"
else
  cargo run -q -p private_pinyin_ai_eval_runner -- "$@"
fi
