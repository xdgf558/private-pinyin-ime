#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

build_dir="$repo_root/build/macos_imk"
module_dir="$build_dir/PrivatePinyinC"
module_cache_dir="$build_dir/module-cache"
app_dir="$repo_root/dist/macos_imk/PrivatePinyin.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
frameworks_dir="$contents_dir/Frameworks"
resources_dir="$contents_dir/Resources"

cargo build -p private_pinyin_ime_ffi

rm -rf "$build_dir" "$app_dir"
mkdir -p "$module_dir" "$module_cache_dir" "$macos_dir" "$frameworks_dir" "$resources_dir"

cat > "$module_dir/module.modulemap" <<MODULEMAP
module PrivatePinyinC [system] {
  header "$repo_root/ffi/c_api.h"
  export *
}
MODULEMAP

swiftc \
  -emit-executable \
  -o "$macos_dir/PrivatePinyin" \
  -I "$module_dir" \
  -module-cache-path "$module_cache_dir" \
  -L "$repo_root/target/debug" \
  -lprivate_pinyin_ime \
  -framework Cocoa \
  -framework InputMethodKit \
  -framework Carbon \
  -Xlinker -rpath \
  -Xlinker "@executable_path/../Frameworks" \
  "$repo_root/platform/macos_imk/Sources/SettingsStore.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift" \
  "$repo_root/platform/macos_imk/Sources/CAbiBridge.swift" \
  "$repo_root/platform/macos_imk/Sources/MacKeyMapper.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinInputController.swift" \
  "$repo_root/platform/macos_imk/Sources/main.swift"

cp "$repo_root/platform/macos_imk/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$repo_root/target/debug/libprivate_pinyin_ime.dylib" \
  "$frameworks_dir/libprivate_pinyin_ime.dylib"

install_name_tool -id "@rpath/libprivate_pinyin_ime.dylib" \
  "$frameworks_dir/libprivate_pinyin_ime.dylib"

original_install_name="$(otool -D "$repo_root/target/debug/libprivate_pinyin_ime.dylib" | tail -n 1)"
install_name_tool -change "$original_install_name" \
  "@rpath/libprivate_pinyin_ime.dylib" \
  "$macos_dir/PrivatePinyin"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$app_dir" >/dev/null
fi

echo "Built $app_dir"
