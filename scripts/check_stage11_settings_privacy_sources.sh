#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "config/default_settings.json"
  "ime_core/src/atomic_file.rs"
  "platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements"
  "platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements"
  "scripts/check_stage11_settings_privacy_sources.sh"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

python3 -m json.tool config/default_settings.json >/dev/null
grep -q '"user_lexicon_path": null' config/default_settings.json

grep -q "packaged_default_settings_json_matches_rust_default" ime_core/tests/settings_tests.rs
grep -q "AtomicFile::create" ime_core/src/settings.rs
grep -q "AtomicFile::create" ime_core/src/user_lexicon.rs
grep -q "replace_file" ime_core/src/atomic_file.rs

if grep -q "remove_file(path)" ime_core/src/settings.rs ime_core/src/user_lexicon.rs; then
  echo "Settings and export writers must use AtomicFile instead of remove+rename." >&2
  exit 1
fi

grep -q "default_settings.json" platform/windows_tsf/src/core_bridge.cpp
grep -q "default_settings.json" platform/windows_tsf/installer/open-settings.ps1
grep -q "default_settings.json" platform/macos_imk/Sources/SettingsStore.swift
grep -q "default_settings.json" scripts/build_macos_imk.sh

if command -v rg >/dev/null 2>&1; then
  if rg -n "CapsLock|Caps Lock" \
    platform/windows_tsf/installer/open-settings.ps1 \
    platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift \
    platform/ios_keyboard/ContainerApp \
    platform/ios_keyboard/KeyboardExtension; then
    echo "Platform settings UI must not expose CapsLock toggle before host support exists." >&2
    exit 1
  fi
else
  if grep -R -nE "CapsLock|Caps Lock" \
    platform/windows_tsf/installer/open-settings.ps1 \
    platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift \
    platform/ios_keyboard/ContainerApp \
    platform/ios_keyboard/KeyboardExtension; then
    echo "Platform settings UI must not expose CapsLock toggle before host support exists." >&2
    exit 1
  fi
fi

grep -q "group.com.privatepinyin.ios" platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements
grep -q "group.com.privatepinyin.ios" platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements
grep -q "appGroupIdentifier" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "settings\\[\"enable_user_learning\"\\] = false" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "Learn selected candidates" platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q "RequestsOpenAccess" platform/ios_keyboard/KeyboardExtension/Info.plist
grep -A1 "RequestsOpenAccess" platform/ios_keyboard/KeyboardExtension/Info.plist | grep -q "<false/>"
grep -q "ime_engine_new(pathPointer)" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_engine_new(nil)" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "configuredEngine ?? ime_engine_new(nil)" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "output.mode == IME_MODE_ENGLISH" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "needsInputModeSwitchKey" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift

if grep -q "englishMode.toggle()" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift; then
  echo "iOS mode UI must derive from C ABI output mode." >&2
  exit 1
fi
