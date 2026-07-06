#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "platform/windows_tsf/src/candidate_window.cpp"
  "platform/windows_tsf/src/candidate_window.h"
  "platform/windows_tsf/src/text_service.cpp"
  "platform/windows_tsf/src/text_service.h"
  "platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift"
  "platform/macos_imk/Sources/PrivatePinyinInputController.swift"
  "platform/macos_imk/Sources/SettingsStore.swift"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

grep -q "GetTextExt" platform/windows_tsf/src/text_service.cpp
grep -q "candidate_anchor_rect" platform/windows_tsf/src/text_service.cpp
grep -q "GetDpiForWindow" platform/windows_tsf/src/candidate_window.cpp
grep -q "AppsUseLightTheme" platform/windows_tsf/src/candidate_window.cpp
grep -q "UnregisterClassW" platform/windows_tsf/src/candidate_window.cpp
grep -q "DLL_PROCESS_DETACH" platform/windows_tsf/src/dllmain.cpp
grep -q "static let shared" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "privatePinyinSettingsChanged" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "PrivatePinyinPreferencesWindowController" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "Preferences..." platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "updateSettings" platform/macos_imk/Sources/SettingsStore.swift
