#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  "docs/ios_testflight_upload_record.md"
  "platform/ios_keyboard/AppStoreMetadata/ExportOptions.plist.template"
  "platform/ios_keyboard/AppStoreMetadata/ExportOptions.upload.plist.template"
  "platform/ios_keyboard/AppStoreMetadata/Signing.env.example"
  "scripts/package_ios_app_store.sh"
  "scripts/check_stage16_ios_testflight_sources.sh"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

validate_plist() {
  python3 -c 'import pathlib, plistlib, sys; plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())' "$1"
}

validate_plist platform/ios_keyboard/AppStoreMetadata/ExportOptions.plist.template
validate_plist platform/ios_keyboard/AppStoreMetadata/ExportOptions.upload.plist.template

bash -n scripts/package_ios_app_store.sh

grep -q "PRIVATE_PINYIN_IOS_DISTRIBUTION_MODE" scripts/package_ios_app_store.sh
grep -q "PRIVATE_PINYIN_IOS_ASC_KEY_PATH" scripts/package_ios_app_store.sh
grep -q "PRIVATE_PINYIN_IOS_ASC_KEY_ID" scripts/package_ios_app_store.sh
grep -q "PRIVATE_PINYIN_IOS_ASC_ISSUER_ID" scripts/package_ios_app_store.sh
grep -q "destination must be 'export' or 'upload'" scripts/package_ios_app_store.sh
grep -q "App Store Connect upload requires" scripts/package_ios_app_store.sh
grep -q -- "-authenticationKeyPath" scripts/package_ios_app_store.sh
grep -q "xcodebuild archive" scripts/package_ios_app_store.sh
grep -q "xcodebuild -exportArchive" scripts/package_ios_app_store.sh
grep -q "package_summary.txt" scripts/package_ios_app_store.sh

grep -q "<string>upload</string>" platform/ios_keyboard/AppStoreMetadata/ExportOptions.upload.plist.template
if grep -q "testFlightInternalTestingOnly" platform/ios_keyboard/AppStoreMetadata/ExportOptions.upload.plist.template; then
  echo "Upload ExportOptions must not force internal-only TestFlight builds." >&2
  exit 1
fi
grep -q "uploadSymbols" platform/ios_keyboard/AppStoreMetadata/ExportOptions.upload.plist.template

grep -q "PRIVATE_PINYIN_IOS_ASC_KEY_PATH" platform/ios_keyboard/AppStoreMetadata/Signing.env.example
grep -q "ExportOptions.upload.plist.template" platform/ios_keyboard/AppStoreMetadata/README.md
grep -q "ios_testflight_upload_record.md" platform/ios_keyboard/AppStoreMetadata/README.md
grep -Fq "*.p8" .gitignore
grep -Fq "platform/ios_keyboard/AppStoreMetadata/ExportOptions*.plist" .gitignore

grep -q "Stage 16" docs/ios_testflight_upload_record.md
grep -q "App Store Connect" docs/ios_testflight_upload_record.md
grep -q "Build appears in App Store Connect" docs/ios_testflight_upload_record.md
grep -q "TestFlight availability" docs/ios_testflight_upload_record.md

echo "Stage 16 iOS TestFlight source checks passed."
