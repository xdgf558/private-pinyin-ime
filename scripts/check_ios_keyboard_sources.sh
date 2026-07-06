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
  "platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements"
  "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift"
  "platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift"
  "platform/ios_keyboard/KeyboardExtension/Info.plist"
  "platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements"
  "scripts/build_ios_keyboard.sh"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

if command -v plutil >/dev/null 2>&1; then
  plutil -lint platform/ios_keyboard/ContainerApp/Info.plist >/dev/null
  plutil -lint platform/ios_keyboard/KeyboardExtension/Info.plist >/dev/null
  plutil -lint platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements >/dev/null
  plutil -lint platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements >/dev/null
else
  grep -q "<plist version=\"1.0\">" platform/ios_keyboard/KeyboardExtension/Info.plist
  grep -q "</plist>" platform/ios_keyboard/KeyboardExtension/Info.plist
fi

grep -q "UIInputViewController" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "advanceToNextInputMode" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "needsInputModeSwitchKey" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "RequestsOpenAccess" platform/ios_keyboard/KeyboardExtension/Info.plist
grep -A1 "RequestsOpenAccess" platform/ios_keyboard/KeyboardExtension/Info.plist | grep -q "<false/>"
grep -q "group.com.privatepinyin.ios" platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements
grep -q "group.com.privatepinyin.ios" platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements
grep -q "CODE_SIGN_ENTITLEMENTS = ContainerApp/PrivatePinyin.entitlements" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "CODE_SIGN_ENTITLEMENTS = KeyboardExtension/PrivatePinyinKeyboard.entitlements" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "default_settings.json in Resources" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "enable_user_learning.*false" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "appGroupIdentifier" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "ime_engine_new(pathPointer)" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_feed_key" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_commit_candidate" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_toggle_mode" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "output.mode == IME_MODE_ENGLISH" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
if grep -q "englishMode.toggle()" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift; then
  echo "iOS keyboard mode UI must derive from C ABI output mode." >&2
  exit 1
fi
grep -q "../../../ffi/c_api.h" platform/ios_keyboard/PrivatePinyinC/module.modulemap
grep -q "crate-type = \\[\"cdylib\", \"staticlib\", \"rlib\"\\]" ffi/ime_ffi/Cargo.toml
grep -q "PrivatePinyinKeyboard.appex in Embed App Extensions" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "com.apple.keyboard-service" platform/ios_keyboard/KeyboardExtension/Info.plist

network_pattern="URLSession|NWConnection|Network.framework|http://|https://"
if command -v rg >/dev/null 2>&1; then
  if rg -n "$network_pattern" \
    --glob "*.swift" \
    platform/ios_keyboard/ContainerApp \
    platform/ios_keyboard/KeyboardExtension; then
    echo "iOS keyboard sources must not include network APIs or URLs." >&2
    exit 1
  fi
else
  found_network_api=0
  while IFS= read -r -d '' swift_file; do
    if grep -nE "$network_pattern" "$swift_file"; then
      found_network_api=1
    fi
  done < <(find platform/ios_keyboard/ContainerApp platform/ios_keyboard/KeyboardExtension -name "*.swift" -print0)

  if [ "$found_network_api" -eq 1 ]; then
    echo "iOS keyboard sources must not include network APIs or URLs." >&2
    exit 1
  fi
fi

if command -v xcodebuild >/dev/null 2>&1; then
  mkdir -p build/ios_keyboard_xcode_home
  HOME="$PWD/build/ios_keyboard_xcode_home" \
    xcodebuild -list -project platform/ios_keyboard/PrivatePinyin.xcodeproj >/dev/null 2>&1
fi
