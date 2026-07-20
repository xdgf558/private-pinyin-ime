#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! command -v swiftc >/dev/null 2>&1; then
  if [[ "${PRIVATE_PINYIN_REQUIRE_SWIFTC:-0}" == "1" ]]; then
    echo "swiftc is required for macOS shared engine tests." >&2
    exit 1
  fi
  echo "swiftc is unavailable; macOS shared engine tests skipped."
  exit 0
fi

cargo build -p private_pinyin_ime_ffi --features desktop-ai

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
mkdir -p "$temporary_dir/PrivatePinyinC" "$temporary_dir/module-cache"

cat > "$temporary_dir/PrivatePinyinC/module.modulemap" <<MODULEMAP
module PrivatePinyinC [system] {
  header "$repo_root/ffi/c_api.h"
  export *
}
MODULEMAP

swiftc \
  -I "$temporary_dir/PrivatePinyinC" \
  -module-cache-path "$temporary_dir/module-cache" \
  -L "$repo_root/target/debug" \
  -lprivate_pinyin_ime \
  -framework Cocoa \
  -framework Carbon \
  -Xlinker -rpath \
  -Xlinker "$repo_root/target/debug" \
  platform/macos_imk/Sources/SettingsStore.swift \
  platform/macos_imk/Sources/CAbiBridge.swift \
  platform/macos_imk/Sources/MacKeyMapper.swift \
  platform/macos_imk/Tests/SharedEnginePoolTests.swift \
  -o "$temporary_dir/shared-engine-pool-tests"

if [[ "${PRIVATE_PINYIN_REPORT_PEAK_RSS:-0}" == "1" ]]; then
  /usr/bin/time -l "$temporary_dir/shared-engine-pool-tests"
else
  "$temporary_dir/shared-engine-pool-tests"
fi
