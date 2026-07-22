#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

network_pattern='(reqwest|ureq|hyper::|tonic::|grpc|TcpStream|UdpSocket|std::net|tokio::net|WebSocket|URLSession|WinHTTP|libcurl|https?://|localhost|127\.0\.0\.1|ollama|lm[ -]?studio|openai|anthropic)'

if rg -n -i "$network_pattern" ai \
  --glob '*.rs' \
  --glob '*.swift' \
  --glob '*.c' \
  --glob '*.cc' \
  --glob '*.cpp' \
  --glob '*.h' \
  --glob '*.m' \
  --glob '*.mm' \
  --glob 'Cargo.toml' \
  --glob '!**/writer_runtime.rs'; then
  echo "Local AI runtime sources must not use network clients or external AI services." >&2
  exit 1
fi

writer_runtime="ai/helper/private_pinyin_ai_helper/src/writer_runtime.rs"
if rg -n -i '(reqwest|ureq|hyper::|tonic::|grpc|UdpSocket|tokio::net|WebSocket|URLSession|WinHTTP|libcurl|https://|"localhost"|0\.0\.0\.0|ollama|lm[ -]?studio|openai|anthropic)' \
  "$writer_runtime"; then
  echo "Writer runtime must not use an external network or third-party local AI service." >&2
  exit 1
fi
grep -q 'Ipv4Addr::LOCALHOST' "$writer_runtime"
grep -q '"127.0.0.1"' "$writer_runtime"
grep -q -- '"--api-key"' "$writer_runtime"
grep -q -- '"--no-webui"' "$writer_runtime"
grep -q -- '"--offline"' "$writer_runtime"
grep -q -- '"--log-disable"' "$writer_runtime"

echo "No external AI service detected; Writer is limited to its authenticated loopback runtime."
