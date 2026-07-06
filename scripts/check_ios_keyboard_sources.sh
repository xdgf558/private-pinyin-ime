#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj"
  "platform/ios_keyboard/PrivatePinyin.xcodeproj/xcshareddata/xcschemes/PrivatePinyin.xcscheme"
  "platform/ios_keyboard/PrivatePinyinC/module.modulemap"
  "platform/ios_keyboard/ContainerApp/PrivatePinyinApp.swift"
  "platform/ios_keyboard/ContainerApp/ContentView.swift"
  "platform/ios_keyboard/ContainerApp/IosSettingsStore.swift"
  "platform/ios_keyboard/ContainerApp/Info.plist"
  "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift"
  "platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift"
  "platform/ios_keyboard/KeyboardExtension/Info.plist"
  "scripts/build_ios_keyboard.sh"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

if command -v plutil >/dev/null 2>&1; then
  plutil -lint platform/ios_keyboard/ContainerApp/Info.plist >/dev/null
  plutil -lint platform/ios_keyboard/KeyboardExtension/Info.plist >/dev/null
else
  grep -q "<plist version=\"1.0\">" platform/ios_keyboard/KeyboardExtension/Info.plist
  grep -q "</plist>" platform/ios_keyboard/KeyboardExtension/Info.plist
fi

grep -q "UIInputViewController" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "advanceToNextInputMode" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "RequestsOpenAccess" platform/ios_keyboard/KeyboardExtension/Info.plist
grep -A1 "RequestsOpenAccess" platform/ios_keyboard/KeyboardExtension/Info.plist | grep -q "<false/>"
grep -q "ime_engine_new" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_feed_key" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_commit_candidate" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_toggle_mode" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "../../../ffi/c_api.h" platform/ios_keyboard/PrivatePinyinC/module.modulemap
grep -q "crate-type = \\[\"cdylib\", \"staticlib\", \"rlib\"\\]" ffi/ime_ffi/Cargo.toml
grep -q "PrivatePinyinKeyboard.appex in Embed App Extensions" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "com.apple.keyboard-service" platform/ios_keyboard/KeyboardExtension/Info.plist

if rg -n "URLSession|NWConnection|Network.framework|http://|https://" \
  --glob "*.swift" \
  platform/ios_keyboard/ContainerApp \
  platform/ios_keyboard/KeyboardExtension; then
  echo "iOS keyboard sources must not include network APIs or URLs in stage 07." >&2
  exit 1
fi

if command -v xcodebuild >/dev/null 2>&1; then
  mkdir -p build/ios_keyboard_xcode_home
  HOME="$PWD/build/ios_keyboard_xcode_home" \
    xcodebuild -list -project platform/ios_keyboard/PrivatePinyin.xcodeproj >/dev/null 2>&1
fi
