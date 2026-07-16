#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash scripts/check_no_external_ai_service.sh
bash scripts/check_ai_privacy_sources.sh

echo "AI-03 privacy guard checks passed."
