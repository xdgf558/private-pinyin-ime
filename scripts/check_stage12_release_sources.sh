#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  "docs/release_distribution_plan.md"
  "docs/macos_public_release_checklist.md"
  "platform/ios_keyboard/AppStoreMetadata/README.md"
  "platform/ios_keyboard/AppStoreMetadata/ExportOptions.plist.template"
  ".github/workflows/windows-package.yml"
  "scripts/check_macos_public_release.sh"
  "scripts/package_ios_app_store.sh"
  "platform/windows_tsf/installer/PrivatePinyinTsf.nsi"
  "platform/windows_tsf/installer/ReleaseNotes.zh-Hans.txt"
  "platform/windows_tsf/installer/PrivatePinyinInstaller.ico"
)

for file in "${required_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "Missing required Stage 12 file: $file" >&2
    exit 1
  fi
done

grep -q "Release Gates" docs/release_distribution_plan.md
grep -q "Automatic Update Strategy" docs/release_distribution_plan.md
grep -q "RequestsOpenAccess=false" docs/release_distribution_plan.md
grep -qi "license" docs/release_distribution_plan.md

grep -q "PRIVATE_PINYIN_MAC_APP_SIGN_IDENTITY" scripts/build_macos_imk.sh
grep -q -- "--options runtime" scripts/build_macos_imk.sh
grep -q "PRIVATE_PINYIN_MAC_INSTALLER_SIGN_IDENTITY" scripts/package_macos_pkg.sh
grep -q "notarytool" scripts/package_macos_pkg.sh
grep -q "stapler" scripts/package_macos_pkg.sh
grep -q "postinstall" scripts/package_macos_pkg.sh
grep -q "pkgutil --check-signature" scripts/check_macos_public_release.sh
grep -q "spctl --assess --type install" scripts/check_macos_public_release.sh
grep -q "stapler validate" scripts/check_macos_public_release.sh
grep -q "shasum -a 256" scripts/check_macos_public_release.sh
grep -q "Website Download Page" docs/macos_public_release_checklist.md
grep -q "Update Flow" docs/macos_public_release_checklist.md

grep -q "Sign-Artifact" scripts/package_windows_tsf.ps1
grep -q "Sign-PowerShellScript" scripts/package_windows_tsf.ps1
grep -q "Set-AuthenticodeSignature" scripts/package_windows_tsf.ps1
grep -q '".ps1"' scripts/package_windows_tsf.ps1
grep -q "RequireSigning" scripts/package_windows_tsf.ps1
grep -q "TimestampUrl" scripts/package_windows_tsf.ps1
grep -q "Resolve-WixToolchain" scripts/package_windows_tsf.ps1
grep -q "Resolve-WixArchitecture" scripts/package_windows_tsf.ps1
grep -q "System64Folder" scripts/package_windows_tsf.ps1
grep -q "target-feature=+crt-static" scripts/package_windows_tsf.ps1
grep -q "CMAKE_MSVC_RUNTIME_LIBRARY" platform/windows_tsf/CMakeLists.txt
grep -q "candle.exe" scripts/package_windows_tsf.ps1
grep -q "Resolve-NsisToolchain" scripts/package_windows_tsf.ps1
grep -q "makensis.exe" scripts/package_windows_tsf.ps1
grep -q "PrivatePinyinInstaller.ico" scripts/package_windows_tsf.ps1
grep -q "ReleaseNotes.zh-Hans.txt" scripts/package_windows_tsf.ps1
grep -q "MUI_ICON" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "RequestExecutionLevel admin" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "DisableX64FSRedirection" platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q "Windows Unsigned Package" .github/workflows/windows-package.yml
grep -q "PrivatePinyin-\${{ inputs.version }}-setup.exe" .github/workflows/windows-package.yml
grep -q "actions/upload-artifact" .github/workflows/windows-package.yml

grep -q "PRIVATE_PINYIN_IOS_TEAM_ID" scripts/package_ios_app_store.sh
grep -q -- "-exportArchive" scripts/package_ios_app_store.sh
grep -q "CODE_SIGNING_REQUIRED=YES" scripts/package_ios_app_store.sh
grep -q "app-store-connect" platform/ios_keyboard/AppStoreMetadata/ExportOptions.plist.template

echo "Stage 12 release packaging scaffold checks passed."
