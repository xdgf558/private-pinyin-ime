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
grep -q 'kPipeReadTimeoutMilliseconds' \
  platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'WaitForExit(60000)' scripts/test_windows_ai_helper.ps1
grep -q 'D:P(A;;GA;;;' platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'BCryptGenRandom' platform/windows_tsf/src/ai_helper_client.cpp
grep -q 'PrivatePinyinAIHelper.exe' \
  platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'PrivatePinyinAIHelper' platform/windows_tsf/installer/PrivatePinyinTsf.wxs

if rg -n 'URLSession|NWConnection|TcpStream|UdpSocket|reqwest|hyper|http://|https://' \
  ai/helper ai/helper_protocol \
  platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift \
  platform/windows_tsf/src/ai_helper_client.cpp; then
  echo "AI-09 helper transport must not use a network or external local service." >&2
  exit 1
fi

cargo test -p private_pinyin_ai_helper_protocol -p private_pinyin_ai_helper

echo "AI-09 desktop Helper source contract passed."
