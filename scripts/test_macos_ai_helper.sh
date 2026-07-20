#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! command -v swiftc >/dev/null 2>&1; then
  if [ "${PRIVATE_PINYIN_REQUIRE_SWIFTC:-0}" = "1" ]; then
    echo "swiftc is required for the macOS AI Helper client test." >&2
    exit 1
  fi
  echo "Skipping macOS AI Helper client test because swiftc is unavailable."
  exit 0
fi

PRIVATE_PINYIN_SKIP_CODESIGN=1 bash scripts/build_macos_imk.sh

test_root="$repo_root/build/macos_ai_helper_test"
test_bundle="$test_root/PrivatePinyin.app"
test_binary="$test_root/ai-helper-client-tests"
module_cache="$test_root/module-cache"
rm -rf "$test_root"
mkdir -p "$test_bundle/Contents/MacOS" "$test_bundle/Contents/Helpers" "$module_cache"
cp "$repo_root/dist/macos_imk/PrivatePinyin.app/Contents/Helpers/PrivatePinyinAIHelper" \
  "$test_bundle/Contents/Helpers/PrivatePinyinAIHelper"
cp "$repo_root/platform/macos_imk/Resources/Info.plist" "$test_bundle/Contents/Info.plist"

swiftc \
  -o "$test_binary" \
  -module-cache-path "$module_cache" \
  -framework Foundation \
  -framework Security \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift" \
  "$repo_root/platform/macos_imk/Tests/AIHelperClientTests.swift"
cp "$test_binary" "$test_bundle/Contents/MacOS/PrivatePinyin"
"$test_bundle/Contents/MacOS/PrivatePinyin"

echo "macOS AI Helper controlled-process test passed."
