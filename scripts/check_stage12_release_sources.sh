#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  "docs/release_distribution_plan.md"
  "platform/ios_keyboard/AppStoreMetadata/README.md"
  "platform/ios_keyboard/AppStoreMetadata/ExportOptions.plist.template"
  "scripts/package_ios_app_store.sh"
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

grep -q "Sign-Artifact" scripts/package_windows_tsf.ps1
grep -q "Sign-PowerShellScript" scripts/package_windows_tsf.ps1
grep -q "Set-AuthenticodeSignature" scripts/package_windows_tsf.ps1
grep -q '".ps1"' scripts/package_windows_tsf.ps1
grep -q "RequireSigning" scripts/package_windows_tsf.ps1
grep -q "TimestampUrl" scripts/package_windows_tsf.ps1

grep -q "PRIVATE_PINYIN_IOS_TEAM_ID" scripts/package_ios_app_store.sh
grep -q -- "-exportArchive" scripts/package_ios_app_store.sh
grep -q "CODE_SIGNING_REQUIRED=YES" scripts/package_ios_app_store.sh
grep -q "app-store-connect" platform/ios_keyboard/AppStoreMetadata/ExportOptions.plist.template

echo "Stage 12 release packaging scaffold checks passed."
