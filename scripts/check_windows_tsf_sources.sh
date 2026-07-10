#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "platform/windows_tsf/CMakeLists.txt"
  "platform/windows_tsf/PrivatePinyinTsf.def"
  "platform/windows_tsf/src/dllmain.cpp"
  "platform/windows_tsf/src/text_service.cpp"
  "platform/windows_tsf/src/text_service.h"
  "platform/windows_tsf/src/key_map.cpp"
  "platform/windows_tsf/src/core_bridge.cpp"
  "platform/windows_tsf/src/candidate_window.cpp"
  "platform/windows_tsf/src/registration.cpp"
  "platform/windows_tsf/installer/register-ime.ps1"
  "platform/windows_tsf/installer/unregister-ime.ps1"
  "platform/windows_tsf/installer/open-settings.ps1"
  "platform/windows_tsf/installer/open-onboarding.ps1"
  "platform/windows_tsf/installer/PrivatePinyinTsf.wxs"
  "platform/windows_tsf/installer/PrivatePinyinTsf.nsi"
  "platform/windows_tsf/installer/PrivatePinyinInstaller.ico"
  "scripts/build_windows_tsf.ps1"
  "scripts/package_windows_tsf.ps1"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

grep -q "ITfTextInputProcessorEx" platform/windows_tsf/src/text_service.h
grep -q "ITfKeyEventSink" platform/windows_tsf/src/text_service.h
grep -q "ITfCompositionSink" platform/windows_tsf/src/text_service.h
grep -q "ITfFunctionProvider" platform/windows_tsf/src/text_service.h
grep -q "ITfFnConfigure" platform/windows_tsf/src/text_service.h
grep -q "AdviseKeyEventSink" platform/windows_tsf/src/text_service.cpp
grep -q "AdviseSingleSink" platform/windows_tsf/src/text_service.cpp
grep -q "open-settings.ps1" platform/windows_tsf/src/text_service.cpp
grep -q "DllRegisterServer" platform/windows_tsf/src/dllmain.cpp
grep -q "DllUnregisterServer" platform/windows_tsf/src/dllmain.cpp
grep -q "DllGetClassObject" platform/windows_tsf/PrivatePinyinTsf.def
grep -q "DllCanUnloadNow" platform/windows_tsf/PrivatePinyinTsf.def
grep -q "RemoveLanguageProfile" platform/windows_tsf/src/registration.cpp
grep -q "ime_session_feed_key" platform/windows_tsf/src/core_bridge.cpp
grep -q "ime_session_reset" platform/windows_tsf/src/core_bridge.cpp
grep -q "ime_engine_clear_user_lexicon" platform/windows_tsf/src/core_bridge.cpp
grep -q "settings.json" platform/windows_tsf/src/core_bridge.cpp
grep -q "猫栈拼音" platform/windows_tsf/src/guids.h
grep -q "IME_KEY_SPACE" platform/windows_tsf/src/key_map.cpp
grep -q "SWP_NOACTIVATE" platform/windows_tsf/src/candidate_window.cpp
grep -q "GetTextExt" platform/windows_tsf/src/text_service.cpp
grep -q "UnregisterClassW" platform/windows_tsf/src/candidate_window.cpp
grep -q "GetDpiForWindow" platform/windows_tsf/src/candidate_window.cpp
grep -q "AppsUseLightTheme" platform/windows_tsf/src/candidate_window.cpp
grep -q "/utf-8" platform/windows_tsf/CMakeLists.txt
grep -q "regsvr32.exe" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "InstallScope=\"perUser\"" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "Impersonate=\"yes\"" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "RequestExecutionLevel admin" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q '!define APP_DIR_NAME "app-${PRODUCT_VERSION}"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'SetOutPath "$INSTDIR\\${APP_DIR_NAME}"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'RMDir /r /REBOOTOK "$INSTDIR\\$2"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'Delete /REBOOTOK "$INSTDIR\\PrivatePinyinTsf.dll"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "PrivatePinyinInstaller.ico" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "猫栈拼音" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "MUI_ICON" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "DisableX64FSRedirection" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'regsvr32.exe" /u /s' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "open-onboarding.ps1" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q ".onInstSuccess" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "IfSilent" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "WindowStyle Hidden" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'MUI_LANGUAGE "SimpChinese"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "INPUTCHARSET" scripts/package_windows_tsf.ps1
grep -q "ms-settings:regionlanguage" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "Set-WinUserLanguageList" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "00286F63-195C-445D-AD40-C6D1A4C560AD" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "HasLegacyInputMethod" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "kLegacyTextServiceProfileGuid" platform/windows_tsf/src/registration.cpp
grep -q "HKEY_CLASSES_ROOT" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "ComponentInstalled" platform/windows_tsf/installer/open-onboarding.ps1
grep -q "添加输入法" platform/windows_tsf/installer/open-onboarding.ps1

onboarding_bom="$(od -An -tx1 -N3 platform/windows_tsf/installer/open-onboarding.ps1 | tr -d ' \n')"
settings_bom="$(od -An -tx1 -N3 platform/windows_tsf/installer/open-settings.ps1 | tr -d ' \n')"
test "$onboarding_bom" = "efbbbf"
test "$settings_bom" = "efbbbf"
