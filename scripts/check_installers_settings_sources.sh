#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "config/default_settings.json"
  "tools/settings_cli/Cargo.toml"
  "tools/settings_cli/src/main.rs"
  "scripts/package_macos_pkg.sh"
  "scripts/package_windows_tsf.ps1"
  "platform/windows_tsf/installer/PrivatePinyinTsf.wxs"
  "platform/windows_tsf/installer/PrivatePinyinTsf.nsi"
  "platform/windows_tsf/installer/open-settings.ps1"
  "platform/windows_tsf/installer/open-onboarding.ps1"
  "platform/windows_tsf/installer/ReleaseNotes.zh-Hans.txt"
  "platform/windows_tsf/installer/PrivatePinyinInstaller.ico"
  "platform/windows_tsf/installer/PrivatePinyinLogo.png"
  "platform/macos_imk/Sources/SettingsStore.swift"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

python3 -m json.tool config/default_settings.json >/dev/null

grep -q "from_json_file_or_default" ime_core/src/settings.rs
grep -q "write_json_file" ime_core/src/settings.rs
grep -q "clear_user_lexicon" ime_core/src/api.rs
grep -q "export_user_lexicon" ime_core/src/api.rs
grep -q "ime_engine_clear_user_lexicon" ffi/c_api.h
grep -q "ime_engine_export_user_lexicon" ffi/c_api.h
grep -q "config_json_path" ffi/c_api.h
grep -q "PrivatePinyinSettingsStore" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "严格隐私模式" platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q "settings.json" platform/windows_tsf/src/core_bridge.cpp
grep -q "default_settings.json" platform/windows_tsf/src/core_bridge.cpp
grep -q "default_settings.json" platform/windows_tsf/installer/open-settings.ps1
grep -q "version.txt" platform/windows_tsf/installer/open-settings.ps1
grep -q 'Text = "常规"' platform/windows_tsf/installer/open-settings.ps1
grep -q 'Text = "隐私与词库"' platform/windows_tsf/installer/open-settings.ps1
grep -q 'Text = "关于"' platform/windows_tsf/installer/open-settings.ps1
grep -q "本版更新" platform/windows_tsf/installer/open-settings.ps1
grep -q "default_settings.json" platform/macos_imk/Sources/SettingsStore.swift
grep -q "default_settings.json" scripts/build_macos_imk.sh
grep -q "PrivatePinyinTsf.wxs" scripts/package_windows_tsf.ps1
grep -q "PrivatePinyinTsf.nsi" scripts/package_windows_tsf.ps1
grep -q "open-onboarding.ps1" scripts/package_windows_tsf.ps1
grep -q "ReleaseNotes.zh-Hans.txt" scripts/package_windows_tsf.ps1
grep -q "PrivatePinyinInstaller.ico" scripts/package_windows_tsf.ps1
grep -q "PrivatePinyinLogo.png" scripts/package_windows_tsf.ps1
grep -q 'Set-Content.*version.txt' scripts/package_windows_tsf.ps1
grep -q "Copy-Item \"config\\\\default_settings.json\"" scripts/package_windows_tsf.ps1
grep -q "InstallScope=\"perUser\"" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "Impersonate=\"yes\"" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "PackagePlatform" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "ComponentWin64" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "RegSvr32Path" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "System64Folder" scripts/package_windows_tsf.ps1
grep -q "RequestExecutionLevel admin" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q '!define APP_DIR_NAME "app-${PRODUCT_VERSION}"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'RMDir /r /REBOOTOK "$INSTDIR\\$2"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "WindowStyle Hidden" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'MUI_LANGUAGE "SimpChinese"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "INPUTCHARSET" scripts/package_windows_tsf.ps1
grep -q "打开语言设置" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "Set-WinUserLanguageList" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "HasLegacyInputMethod" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "ITfFnConfigure" platform/windows_tsf/src/text_service.h
grep -q "open-settings.ps1" platform/windows_tsf/src/text_service.cpp
grep -q "猫栈拼音偏好设置" platform/windows_tsf/installer/open-settings.ps1
grep -q "pkgbuild" scripts/package_macos_pkg.sh
