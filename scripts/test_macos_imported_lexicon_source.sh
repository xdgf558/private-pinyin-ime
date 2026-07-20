#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! command -v swiftc >/dev/null 2>&1; then
  if [[ "${PRIVATE_PINYIN_REQUIRE_SWIFTC:-0}" == "1" ]]; then
    echo "swiftc is required for macOS imported lexicon source tests." >&2
    exit 1
  fi
  echo "swiftc is unavailable; macOS imported lexicon source tests skipped."
  exit 0
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

swiftc \
  platform/macos_imk/Sources/SettingsStore.swift \
  platform/macos_imk/Tests/ImportedLexiconSourceTests.swift \
  -o "$temporary_dir/imported-lexicon-source-tests"

"$temporary_dir/imported-lexicon-source-tests"
