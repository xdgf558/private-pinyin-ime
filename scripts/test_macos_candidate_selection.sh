#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null 2>&1; then
  if [[ "${PRIVATE_PINYIN_REQUIRE_SWIFTC:-0}" == "1" ]]; then
    echo "swiftc is required for macOS candidate selection tests." >&2
    exit 1
  fi
  echo "swiftc is unavailable; macOS candidate selection tests skipped."
  exit 0
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
mkdir -p "$temporary_dir/module-cache"

swiftc \
  -module-cache-path "$temporary_dir/module-cache" \
  platform/macos_imk/Sources/PrivatePinyinCandidateSelectionState.swift \
  platform/macos_imk/Tests/CandidateSelectionStateTests.swift \
  -o "$temporary_dir/candidate-selection-tests"

"$temporary_dir/candidate-selection-tests"
