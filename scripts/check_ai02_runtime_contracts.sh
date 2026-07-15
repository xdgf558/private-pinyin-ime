#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ai/local_ai_core/Cargo.toml"
  "ai/local_ai_core/src/lib.rs"
  "ai/local_ai_core/src/budget.rs"
  "ai/local_ai_core/src/error.rs"
  "ai/local_ai_core/src/feature.rs"
  "ai/local_ai_core/src/hardware.rs"
  "ai/local_ai_core/src/identity.rs"
  "ai/local_ai_core/src/mock_provider.rs"
  "ai/local_ai_core/src/provider.rs"
  "ai/local_ai_core/src/request.rs"
  "ai/local_ai_core/src/response.rs"
  "ai/local_ai_core/src/tests.rs"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required AI-02 file: $file" >&2
    exit 1
  fi
done

grep -q 'ai/local_ai_core' Cargo.toml
grep -q 'AiRequestIdentity' ai/local_ai_core/src/identity.rs
grep -q 'AiCompositionRevision' ai/local_ai_core/src/identity.rs
grep -q 'AiCandidateSetHash' ai/local_ai_core/src/identity.rs
grep -q 'AiDeadline' ai/local_ai_core/src/budget.rs
grep -q 'trait LocalAiProvider: Send + Sync' ai/local_ai_core/src/provider.rs
grep -q 'fn cancel(&self, identity: AiRequestIdentity)' ai/local_ai_core/src/provider.rs
grep -q 'private-pinyin-mock-v1' ai/local_ai_core/src/mock_provider.rs
grep -q '<redacted>' ai/local_ai_core/src/request.rs
grep -q '<redacted>' ai/local_ai_core/src/response.rs

if rg -n '(reqwest|hyper::|TcpStream|UdpSocket|WebSocket|localhost|https?://|ollama)' \
  ai/local_ai_core/Cargo.toml ai/local_ai_core/src; then
  echo "AI-02 local_ai_core must not contain network or external-service dependencies" >&2
  exit 1
fi

if rg -n '(ime_core|ime_ffi|platform/)' ai/local_ai_core/Cargo.toml ai/local_ai_core/src; then
  echo "AI-02 local_ai_core must remain isolated from the engine, FFI, and platform hosts" >&2
  exit 1
fi

cargo test -p private_pinyin_local_ai_core

echo "AI-02 runtime contract checks passed."
