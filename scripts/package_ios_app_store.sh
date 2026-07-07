#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

rust_target="${IOS_RUST_TARGET:-aarch64-apple-ios}"
sdk="${IOS_SDK:-iphoneos}"
configuration="${CONFIGURATION:-Release}"
deployment_target="${IOS_DEPLOYMENT_TARGET:-18.0}"
team_id="${PRIVATE_PINYIN_IOS_TEAM_ID:-}"
export_options="${PRIVATE_PINYIN_IOS_EXPORT_OPTIONS:-}"
project="$repo_root/platform/ios_keyboard/PrivatePinyin.xcodeproj"
archive_path="$repo_root/dist/ios/PrivatePinyin.xcarchive"
export_path="$repo_root/dist/ios/export"
derived_data="$repo_root/build/ios_keyboard_release"

if [ -z "$team_id" ]; then
  echo "PRIVATE_PINYIN_IOS_TEAM_ID is required for an App Store archive." >&2
  exit 1
fi

if [ -z "$export_options" ] || [ ! -f "$export_options" ]; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must point to an ExportOptions.plist." >&2
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
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  clean archive

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$export_path"

echo "Built iOS archive: $archive_path"
echo "Exported iOS artifact to: $export_path"
