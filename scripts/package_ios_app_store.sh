#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

rust_target="${IOS_RUST_TARGET:-aarch64-apple-ios}"
sdk="${IOS_SDK:-iphoneos}"
configuration="${CONFIGURATION:-Release}"
deployment_target="${IOS_DEPLOYMENT_TARGET:-18.0}"
team_id="${PRIVATE_PINYIN_IOS_TEAM_ID:-}"
app_bundle_id="${PRIVATE_PINYIN_IOS_APP_BUNDLE_ID:-}"
keyboard_bundle_id="${PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID:-}"
app_group_id="${PRIVATE_PINYIN_IOS_APP_GROUP_ID:-}"
export_options="${PRIVATE_PINYIN_IOS_EXPORT_OPTIONS:-}"
project="$repo_root/platform/ios_keyboard/PrivatePinyin.xcodeproj"
archive_path="$repo_root/dist/ios/PrivatePinyin.xcarchive"
export_path="$repo_root/dist/ios/export"
derived_data="$repo_root/build/ios_keyboard_release"

if [ -z "$team_id" ]; then
  echo "PRIVATE_PINYIN_IOS_TEAM_ID is required for an App Store archive." >&2
  exit 1
fi

if [ -z "$app_bundle_id" ]; then
  echo "PRIVATE_PINYIN_IOS_APP_BUNDLE_ID is required for an App Store archive." >&2
  exit 1
fi

if [ -z "$keyboard_bundle_id" ]; then
  echo "PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID is required for an App Store archive." >&2
  exit 1
fi

if [ -z "$app_group_id" ]; then
  echo "PRIVATE_PINYIN_IOS_APP_GROUP_ID is required for an App Store archive." >&2
  exit 1
fi

case "$app_group_id" in
  group.*) ;;
  *)
    echo "PRIVATE_PINYIN_IOS_APP_GROUP_ID must start with 'group.'." >&2
    exit 1
    ;;
esac

if [ -z "$export_options" ] || [ ! -f "$export_options" ]; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must point to an ExportOptions.plist." >&2
  exit 1
fi

if ! grep -Fq "<string>$team_id</string>" "$export_options"; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must include teamID '$team_id'." >&2
  exit 1
fi

if ! grep -Fq "<key>$app_bundle_id</key>" "$export_options"; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must include provisioning profile for app bundle '$app_bundle_id'." >&2
  exit 1
fi

if ! grep -Fq "<key>$keyboard_bundle_id</key>" "$export_options"; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must include provisioning profile for keyboard bundle '$keyboard_bundle_id'." >&2
  exit 1
fi

if ! rustup target list --installed | grep -qx "$rust_target"; then
  echo "Missing Rust target: $rust_target" >&2
  echo "Install it with: rustup target add $rust_target" >&2
  exit 1
fi

mkdir -p "$(dirname "$archive_path")" "$export_path"

export IPHONEOS_DEPLOYMENT_TARGET="$deployment_target"
cargo build -p private_pinyin_ime_ffi --release --target "$rust_target"

xcodebuild archive \
  -project "$project" \
  -scheme PrivatePinyin \
  -configuration "$configuration" \
  -sdk "$sdk" \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data" \
  IOS_RUST_TARGET="$rust_target" \
  IPHONEOS_DEPLOYMENT_TARGET="$deployment_target" \
  DEVELOPMENT_TEAM="$team_id" \
  PRIVATE_PINYIN_IOS_APP_BUNDLE_ID="$app_bundle_id" \
  PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID="$keyboard_bundle_id" \
  PRIVATE_PINYIN_IOS_APP_GROUP_ID="$app_group_id" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  clean archive

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$export_path"

echo "Built iOS archive: $archive_path"
echo "Exported iOS artifact to: $export_path"
