#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "platform/macos_imk/Sources/SettingsStore.swift"
  "platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift"
  "platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift"
  "platform/macos_imk/Sources/PrivatePinyinUpdateController.swift"
  "platform/macos_imk/Sources/UpdateManifest.swift"
  "platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift"
  "platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift"
  "platform/macos_imk/Sources/PrivatePinyinProcessRefreshPolicy.swift"
  "platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift"
  "platform/macos_imk/Sources/CAbiBridge.swift"
  "platform/macos_imk/Sources/MacKeyMapper.swift"
  "platform/macos_imk/Sources/PrivatePinyinInputController.swift"
  "platform/macos_imk/Tests/SharedEnginePoolTests.swift"
  "platform/macos_imk/Sources/main.swift"
  "platform/macos_imk/Resources/Info.plist"
  "platform/macos_imk/Resources/InfoPlist.loctable"
  "platform/macos_imk/Resources/PrivatePinyinMenuIcon.tif"
  "platform/macos_imk/Resources/PrivatePinyinAppIcon.icns"
  "platform/macos_imk/Resources/ReleaseNotes.zh-Hans.txt"
  "platform/macos_imk/Resources/en.lproj/InfoPlist.strings"
  "platform/macos_imk/Resources/zh-Hans.lproj/InfoPlist.strings"
  "platform/macos_imk/installer/install-local.sh"
  "platform/macos_imk/installer/uninstall-local.sh"
  "scripts/build_macos_imk.sh"
  "scripts/test_macos_shared_engine.sh"
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

if command -v iconutil >/dev/null 2>&1; then
  iconset_dir="$(mktemp -d)"
  iconutil -c iconset \
    platform/macos_imk/Resources/PrivatePinyinAppIcon.icns \
    -o "$iconset_dir/PrivatePinyinAppIcon.iconset" >/dev/null
  test -f "$iconset_dir/PrivatePinyinAppIcon.iconset/icon_16x16.png"
  test -f "$iconset_dir/PrivatePinyinAppIcon.iconset/icon_32x32.png"
  test -f "$iconset_dir/PrivatePinyinAppIcon.iconset/icon_128x128.png"
  test -f "$iconset_dir/PrivatePinyinAppIcon.iconset/icon_256x256.png"
  test -f "$iconset_dir/PrivatePinyinAppIcon.iconset/icon_512x512.png"
  rm -rf "$iconset_dir"
fi

if command -v tiffutil >/dev/null 2>&1; then
  menu_icon_info="$(tiffutil -info platform/macos_imk/Resources/PrivatePinyinMenuIcon.tif)"
  grep -q "Image Width: 16" <<<"$menu_icon_info"
  grep -q "Image Width: 32" <<<"$menu_icon_info"
fi

grep -q "IMKServer" platform/macos_imk/Sources/main.swift
grep -q "IMKInputController" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "IMKCandidates" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "kIMKSingleRowSteppingCandidatePanel" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "setSelectionKeys(selectionKeyCodes)" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "IMKCandidatesSendServerKeyEventFirst: true" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "PrivatePinyinCandidatePanelStore" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "static var panel: IMKCandidates" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "sharedPanel(for: server)" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "macOSCandidatePageSize = 9" platform/macos_imk/Sources/SettingsStore.swift
grep -q "repairRuntimeSettingsIfNeeded" platform/macos_imk/Sources/SettingsStore.swift
grep -q "ime_session_feed_key" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "ime_session_reset" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "ime_engine_clear_user_lexicon" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "ime_engine_import_rime_lexicon" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "ime_engine_clear_imported_lexicon" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "PrivatePinyinSettingsStore" platform/macos_imk/Sources/SettingsStore.swift
grep -q "ime_engine_new(nil)" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "SharedPinyinEnginePool" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "static let shared = SharedPinyinEnginePool" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "error code=shared_engine_rebuild_failed" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "sharedEngineLoadCountForTesting" platform/macos_imk/Sources/CAbiBridge.swift
grep -q "multiple macOS client controllers share one parsed engine" platform/macos_imk/Tests/SharedEnginePoolTests.swift
grep -q "PrivatePinyinPreferencesWindowController" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "StationToggle" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "StationButton" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "NSTrackingArea" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "window.appearance = NSAppearance(named: .darkAqua)" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "\.resizable" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "contentAspectRatio" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "allowsMagnification = false" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "windowDidResize" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "猫栈拼音偏好设置" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "严格隐私模式" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "记住你常选的词" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "打开设置文件" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "本地导入词库" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "importedLexiconStatusLabel" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "importedLexiconSummaryText" platform/macos_imk/Sources/SettingsStore.swift
grep -q "imported_lexicon_manifest.json" platform/macos_imk/Sources/SettingsStore.swift
grep -q "a small station, still lit at night" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "STATION BOARD" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "CFBundleShortVersionString" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "ReleaseNotes.zh-Hans" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "本次更新" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "PrivatePinyinOnboardingWindowController" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "StationTheme" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "NSTrackingArea" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "window.appearance = NSAppearance(named: .darkAqua)" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "brandRow.widthAnchor.constraint(equalTo: root.widthAnchor)" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "输入法已经装好了" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "window.title = \"猫栈拼音设置\"" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "把「猫栈拼音」加进系统输入源" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "打开键盘设置" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q -- "--show-onboarding" platform/macos_imk/Sources/main.swift
grep -q -- "--show-preferences" platform/macos_imk/Sources/main.swift
grep -q "postinstall" scripts/package_macos_pkg.sh
grep -q "launchctl asuser" scripts/package_macos_pkg.sh
grep -q "TISInputSourceID" platform/macos_imk/Resources/Info.plist
grep -q "smSimpChinese" platform/macos_imk/Resources/Info.plist
grep -A1 "tsInputModeDefaultStateKey" platform/macos_imk/Resources/Info.plist | grep -q "<false/>"
grep -q "CFBundleIconFile" platform/macos_imk/Resources/Info.plist
grep -q "PrivatePinyinAppIcon" platform/macos_imk/Resources/Info.plist
grep -q "tsInputModeMenuIconFileKey" platform/macos_imk/Resources/Info.plist
grep -q "tsInputModeAlternateMenuIconFileKey" platform/macos_imk/Resources/Info.plist
grep -q "tsInputModePaletteIconFileKey" platform/macos_imk/Resources/Info.plist
grep -q "tsInputMethodIconFileKey" platform/macos_imk/Resources/Info.plist
grep -q "PrivatePinyinMenuIcon.tif" platform/macos_imk/Resources/Info.plist
grep -q "猫栈拼音" platform/macos_imk/Resources/InfoPlist.loctable
grep -q "猫栈" platform/macos_imk/Resources/Info.plist
grep -q "zh_Hans" platform/macos_imk/Resources/InfoPlist.loctable
grep -q "猫栈拼音" platform/macos_imk/Resources/zh-Hans.lproj/InfoPlist.strings
grep -q "猫栈拼音" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "station cat · input method" platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q "InfoPlist.loctable" scripts/build_macos_imk.sh
grep -q "PrivatePinyinMenuIcon.tif" scripts/build_macos_imk.sh
grep -q "PrivatePinyinAppIcon.icns" scripts/build_macos_imk.sh
grep -q "ReleaseNotes.zh-Hans.txt" scripts/build_macos_imk.sh
grep -q "zh-Hans.lproj" scripts/build_macos_imk.sh
grep -q "COPYFILE_DISABLE=1" scripts/build_macos_imk.sh
grep -q "COPYFILE_DISABLE=1" scripts/package_macos_pkg.sh
grep -q "xattr -cr" scripts/build_macos_imk.sh
grep -q "xattr -cr" scripts/package_macos_pkg.sh
grep -q "偏好设置..." platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "NSWindow" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "严格隐私模式" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "清空用户词库" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "导出用户词库" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "导入 Rime 词库" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "清空导入词库" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "打开设置文件" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "updateComposition" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "InputMethodConnectionName" platform/macos_imk/Resources/Info.plist
grep -q "PrivatePinyinUpdateController" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "PrivatePinyinUpdateController" platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q "UpdateManifest.swift" scripts/build_macos_imk.sh
grep -q "PrivatePinyinPackageVerifier.swift" scripts/build_macos_imk.sh
grep -q "PrivatePinyinPackageDownloader.swift" scripts/build_macos_imk.sh
grep -q "PrivatePinyinUpdateController.swift" scripts/build_macos_imk.sh
grep -q "PrivatePinyinProcessRefreshPolicy.swift" scripts/build_macos_imk.sh
grep -q "PrivatePinyinPostInstallController.swift" scripts/build_macos_imk.sh
