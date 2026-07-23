#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

build_dir="$repo_root/build/macos_imk"
module_dir="$build_dir/PrivatePinyinC"
module_cache_dir="$build_dir/module-cache"
app_dir="$repo_root/dist/macos_imk/PrivatePinyin.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
frameworks_dir="$contents_dir/Frameworks"
helpers_dir="$contents_dir/Helpers"
resources_dir="$contents_dir/Resources"
codesign_identity="${PRIVATE_PINYIN_MAC_APP_SIGN_IDENTITY:--}"
skip_codesign="${PRIVATE_PINYIN_SKIP_CODESIGN:-0}"

cargo build -p private_pinyin_ime_ffi --features desktop-ai
cargo build -p private_pinyin_ai_helper --release

rm -rf "$build_dir" "$app_dir"
mkdir -p "$module_dir" "$module_cache_dir" "$macos_dir" "$frameworks_dir" "$helpers_dir" "$resources_dir"

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
  -framework Security \
  -Xlinker -rpath \
  -Xlinker "@executable_path/../Frameworks" \
  "$repo_root/platform/macos_imk/Sources/SettingsStore.swift" \
  "$repo_root/platform/macos_imk/Sources/UpdateManifest.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinUpdateController.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinProcessRefreshPolicy.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinLaunchPolicy.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinInputSourceRegistration.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinWriterModelManager.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinWriterWindowController.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinAIHelperClient.swift" \
  "$repo_root/platform/macos_imk/Sources/CAbiBridge.swift" \
  "$repo_root/platform/macos_imk/Sources/MacKeyMapper.swift" \
  "$repo_root/platform/macos_imk/Sources/PrivatePinyinInputController.swift" \
  "$repo_root/platform/macos_imk/Sources/main.swift"

cp "$repo_root/platform/macos_imk/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$repo_root/platform/macos_imk/Resources/InfoPlist.loctable" "$resources_dir/InfoPlist.loctable"
cp "$repo_root/platform/macos_imk/Resources/PrivatePinyinMenuIcon.tif" "$resources_dir/PrivatePinyinMenuIcon.tif"
cp "$repo_root/platform/macos_imk/Resources/PrivatePinyinAppIcon.icns" "$resources_dir/PrivatePinyinAppIcon.icns"
cp "$repo_root/platform/macos_imk/Resources/ReleaseNotes.zh-Hans.txt" "$resources_dir/ReleaseNotes.zh-Hans.txt"
cp -R "$repo_root/platform/macos_imk/Resources/en.lproj" "$resources_dir/en.lproj"
cp -R "$repo_root/platform/macos_imk/Resources/zh-Hans.lproj" "$resources_dir/zh-Hans.lproj"
cp "$repo_root/config/default_settings.json" "$resources_dir/default_settings.json"
cp "$repo_root/target/debug/libprivate_pinyin_ime.dylib" \
  "$frameworks_dir/libprivate_pinyin_ime.dylib"
cp "$repo_root/target/release/private_pinyin_ai_helper" \
  "$helpers_dir/PrivatePinyinAIHelper"
chmod 755 "$helpers_dir/PrivatePinyinAIHelper"
bash "$repo_root/scripts/prepare_macos_writer_runtime.sh" \
  "$helpers_dir/WriterRuntime"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$app_dir" || true
fi

install_name_tool -id "@rpath/libprivate_pinyin_ime.dylib" \
  "$frameworks_dir/libprivate_pinyin_ime.dylib"

original_install_name="$(otool -D "$repo_root/target/debug/libprivate_pinyin_ime.dylib" | tail -n 1)"
install_name_tool -change "$original_install_name" \
  "@rpath/libprivate_pinyin_ime.dylib" \
  "$macos_dir/PrivatePinyin"

if [ "$skip_codesign" != "1" ] && command -v codesign >/dev/null 2>&1; then
  codesign_args=(--force --deep --sign "$codesign_identity")
  if [ "$codesign_identity" != "-" ]; then
    codesign_args+=(--options runtime --timestamp)
  fi
  while IFS= read -r runtime_binary; do
    codesign "${codesign_args[@]}" "$runtime_binary" >/dev/null
  done < <(find "$helpers_dir/WriterRuntime" -type f \( -name 'llama-server' -o -name '*.dylib' \) -print)
  codesign "${codesign_args[@]}" "$helpers_dir/PrivatePinyinAIHelper" >/dev/null
  codesign "${codesign_args[@]}" "$app_dir" >/dev/null
fi

echo "Built $app_dir"
