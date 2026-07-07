#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "platform/macos_imk/Sources/SettingsStore.swift"
  "platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift"
  "platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift"
  "platform/macos_imk/Sources/CAbiBridge.swift"
  "platform/macos_imk/Sources/MacKeyMapper.swift"
  "platform/macos_imk/Sources/PrivatePinyinInputController.swift"
  "platform/macos_imk/Sources/main.swift"
  "platform/macos_imk/Resources/Info.plist"
  "platform/macos_imk/installer/install-local.sh"
  "platform/macos_imk/installer/uninstall-local.sh"
  "scripts/build_macos_imk.sh"
  "scripts/package_macos_pkg.sh"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

if command -v plutil >/dev/null 2>&1; then
  plutil -lint platform/macos_imk/Resources/Info.plist >/dev/null
else
  grep -q "<plist version=\"1.0\">" platform/macos_imk/Resources/Info.plist
  grep -q "</plist>" platform/macos_imk/Resources/Info.plist
fi

grep -q "IMKServer" platform/macos_imk/Sources/main.swift
grep -q "IMKInputController" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "IMKCandidates" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "ime_session_feed_key" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "ime_session_reset" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "ime_engine_clear_user_lexicon" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "PrivatePinyinSettingsStore" platform/macos_imk/Sources/SettingsStore.swift
grep -q "PrivatePinyinPreferencesWindowController" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "PrivatePinyinOnboardingWindowController" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "StationTheme" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "NSTrackingArea" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "window.appearance = NSAppearance(named: .darkAqua)" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "输入法已经装好了" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "打开键盘设置" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q -- "--show-onboarding" platform/macos_imk/Sources/main.swift
grep -q "postinstall" scripts/package_macos_pkg.sh
grep -q "launchctl asuser" scripts/package_macos_pkg.sh
grep -q "TISInputSourceID" platform/macos_imk/Resources/Info.plist
grep -q "smSimpChinese" platform/macos_imk/Resources/Info.plist
grep -q "Preferences..." platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "NSWindow" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "Strict Privacy Mode" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "updateComposition" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "InputMethodConnectionName" platform/macos_imk/Resources/Info.plist
