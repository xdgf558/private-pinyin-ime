#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcrun >/dev/null 2>&1; then
  if [[ "${PRIVATE_PINYIN_REQUIRE_SWIFTC:-0}" == "1" ]]; then
    echo "xcrun is required for the iOS Chinese transform regression." >&2
    exit 1
  fi
  echo "Skipping iOS Chinese transform regression: xcrun is unavailable."
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cp platform/ios_keyboard/Tests/ChineseTextConverterRegression.swift "$tmp_dir/main.swift"

xcrun swiftc \
  platform/ios_keyboard/ContainerApp/IosSettingsStore.swift \
  "$tmp_dir/main.swift" \
  -o "$tmp_dir/ios-chinese-transform-regression"

"$tmp_dir/ios-chinese-transform-regression"
