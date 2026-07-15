#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc is unavailable; UPDATE-03 process refresh policy tests skipped."
  exit 0
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
mkdir -p "$temporary_dir/module-cache"

swiftc \
  -module-cache-path "$temporary_dir/module-cache" \
  platform/macos_imk/Sources/PrivatePinyinProcessRefreshPolicy.swift \
  platform/macos_imk/Tests/ProcessRefreshPolicyTests.swift \
  -o "$temporary_dir/process-refresh-policy-tests"

"$temporary_dir/process-refresh-policy-tests"
