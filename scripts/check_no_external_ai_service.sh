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
  --glob 'Cargo.toml'; then
  echo "Local AI runtime sources must not use network clients or external AI services." >&2
  exit 1
fi

echo "No external AI service or network runtime source detected."
