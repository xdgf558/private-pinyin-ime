#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc is unavailable; macOS update manifest runtime tests skipped."
  exit 0
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
mkdir -p "$temporary_dir/module-cache"

swiftc \
  -module-cache-path "$temporary_dir/module-cache" \
  platform/macos_imk/Sources/UpdateManifest.swift \
  platform/macos_imk/Tests/UpdateManifestTests.swift \
  -o "$temporary_dir/update-manifest-tests"

"$temporary_dir/update-manifest-tests" \
  platform/macos_imk/Tests/Fixtures/stable-update.json
