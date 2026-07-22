#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  "ai/helper_protocol/Cargo.toml"
  "ai/helper_protocol/src/lib.rs"
  "ai/helper/private_pinyin_ai_helper/Cargo.toml"
  "ai/helper/private_pinyin_ai_helper/src/main.rs"
  "platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift"
  "platform/macos_imk/Tests/AIHelperClientTests.swift"
  "platform/windows_tsf/src/ai_helper_client.cpp"
  "platform/windows_tsf/src/ai_helper_client.h"
  "platform/windows_tsf/src/ai_helper_probe_main.cpp"
  "scripts/test_macos_ai_helper.sh"
  "scripts/test_windows_ai_helper.ps1"
)
for file in "${required_files[@]}"; do
  test -f "$file"
done

grep -q 'MAX_HELPER_PAYLOAD_BYTES: usize = 64 \* 1024' \
  ai/helper_protocol/src/lib.rs
grep -q 'DEFAULT_HELPER_IDLE_TIMEOUT: Duration = Duration::from_secs(600)' \
  ai/helper_protocol/src/lib.rs
grep -q 'constant_time_equal' ai/helper_protocol/src/lib.rs
grep -q '"<redacted>"' ai/helper_protocol/src/lib.rs
grep -q 'sync_channel::<HelperFrame>(MAX_HELPER_RESPONSE_QUEUE)' \
  ai/helper/private_pinyin_ai_helper/src/main.rs
grep -q 'reap_finished_workers(&mut worker_threads)' \
  ai/helper/private_pinyin_ai_helper/src/main.rs
grep -q 'PRIVATE_PINYIN_AI_HELPER_TOKEN' \
  ai/helper/private_pinyin_ai_helper/src/main.rs
grep -q '"--request-pipe"' \
  ai/helper/private_pinyin_ai_helper/src/main.rs
grep -q '"--response-pipe"' \
  ai/helper/private_pinyin_ai_helper/src/main.rs
grep -q 'SecRandomCopyBytes' \
  platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift
grep -q 'Process()' \
  platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift
grep -q 'transportGeneration' \
  platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift
grep -q 'PIPE_REJECT_REMOTE_CLIENTS' \
  platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'PIPE_ACCESS_OUTBOUND' \
  platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'PIPE_ACCESS_INBOUND' \
  platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'wait_for_pipe_connection' \
  platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'GetNamedPipeClientProcessId' \
  platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'kPipeReadTimeoutMilliseconds' \
  platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'WaitForExit(60000)' scripts/test_windows_ai_helper.ps1
grep -q 'D:P(A;;GA;;;' platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'BCryptGenRandom' platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'PrivatePinyinAIHelper.exe' \
  platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'PrivatePinyinAIHelper' platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q 'cargo build -p private_pinyin_ai_helper --release' \
  scripts/build_macos_imk.sh
grep -q 'target/release/private_pinyin_ai_helper' scripts/build_macos_imk.sh

if rg -n 'URLSession|NWConnection|TcpStream|UdpSocket|reqwest|hyper|http://|https://' \
  ai/helper ai/helper_protocol \
  --glob '!**/writer_runtime.rs' \
  platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift \
  platform/windows_tsf/src/ai_helper_client.cpp; then
  echo "AI-09 helper transport must not use a network or external local service." >&2
  exit 1
fi

writer_runtime="ai/helper/private_pinyin_ai_helper/src/writer_runtime.rs"
if rg -n -i 'URLSession|NWConnection|UdpSocket|reqwest|ureq|hyper::|tonic::|grpc|tokio::net|WebSocket|WinHTTP|libcurl|https://|ollama|lm[ -]?studio|openai|anthropic|0\.0\.0\.0' \
  "$writer_runtime"; then
  echo "Writer runtime may only use its authenticated, project-owned loopback server." >&2
  exit 1
fi
grep -q 'Ipv4Addr::LOCALHOST' "$writer_runtime"
grep -q '"127.0.0.1"' "$writer_runtime"
grep -q 'WriterRuntime::new()' ai/helper/private_pinyin_ai_helper/src/main.rs
grep -q 'getrandom::fill' "$writer_runtime"
grep -q -- '"--api-key-file"' "$writer_runtime"
if grep -q -- '"--api-key"' "$writer_runtime"; then
  echo "Writer server secrets must not enter process arguments." >&2
  exit 1
fi
grep -q -- '"--no-webui"' "$writer_runtime"
grep -q -- '"--offline"' "$writer_runtime"
grep -q -- '"--log-disable"' "$writer_runtime"

cargo test -p private_pinyin_ai_helper_protocol -p private_pinyin_ai_helper

echo "AI-09 desktop Helper source contract passed."
