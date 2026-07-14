#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "UPDATE-02 package verifier tests require macOS; skipped."
  exit 0
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc is unavailable; UPDATE-02 package verifier tests skipped."
  exit 0
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
mkdir -p "$temporary_dir/module-cache"

swiftc \
  -module-cache-path "$temporary_dir/module-cache" \
  platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift \
  platform/macos_imk/Tests/UpdatePackageVerifierTests.swift \
  -o "$temporary_dir/update-package-verifier-tests"

"$temporary_dir/update-package-verifier-tests"
