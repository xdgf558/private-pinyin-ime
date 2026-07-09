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
grep -q "AdviseKeyEventSink" platform/windows_tsf/src/text_service.cpp
grep -q "DllRegisterServer" platform/windows_tsf/src/dllmain.cpp
grep -q "DllUnregisterServer" platform/windows_tsf/src/dllmain.cpp
grep -q "DllGetClassObject" platform/windows_tsf/PrivatePinyinTsf.def
grep -q "DllCanUnloadNow" platform/windows_tsf/PrivatePinyinTsf.def
grep -q "RemoveLanguageProfile" platform/windows_tsf/src/registration.cpp
grep -q "ime_session_feed_key" platform/windows_tsf/src/core_bridge.cpp
grep -q "ime_session_reset" platform/windows_tsf/src/core_bridge.cpp
grep -q "ime_engine_clear_user_lexicon" platform/windows_tsf/src/core_bridge.cpp
grep -q "settings.json" platform/windows_tsf/src/core_bridge.cpp
grep -q "IME_KEY_SPACE" platform/windows_tsf/src/key_map.cpp
grep -q "SWP_NOACTIVATE" platform/windows_tsf/src/candidate_window.cpp
grep -q "GetTextExt" platform/windows_tsf/src/text_service.cpp
grep -q "UnregisterClassW" platform/windows_tsf/src/candidate_window.cpp
grep -q "GetDpiForWindow" platform/windows_tsf/src/candidate_window.cpp
grep -q "AppsUseLightTheme" platform/windows_tsf/src/candidate_window.cpp
grep -q "regsvr32.exe" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "InstallScope=\"perUser\"" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "Impersonate=\"yes\"" platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q "RequestExecutionLevel admin" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "PrivatePinyinInstaller.ico" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "MUI_ICON" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "DisableX64FSRedirection" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'regsvr32.exe" /u /s' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "open-onboarding.ps1" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "ms-settings:regionlanguage" platform/windows_tsf/installer/open-onboarding.ps1
