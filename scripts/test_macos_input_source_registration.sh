#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! command -v swiftc >/dev/null 2>&1; then
  if [ "${PRIVATE_PINYIN_REQUIRE_SWIFTC:-0}" = "1" ]; then
    echo "swiftc is required for macOS input source registration tests" >&2
    exit 1
  fi
  echo "Skipping macOS input source registration tests: swiftc is unavailable."
  exit 0
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
mkdir -p "$temporary_dir/module-cache"

swiftc \
  -module-cache-path "$temporary_dir/module-cache" \
  -o "$temporary_dir/input-source-registration-tests" \
  -framework Carbon \
  platform/macos_imk/Sources/PrivatePinyinInputSourceRegistration.swift \
  platform/macos_imk/Tests/InputSourceRegistrationTests.swift
"$temporary_dir/input-source-registration-tests"
