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
distribution_mode="${PRIVATE_PINYIN_IOS_DISTRIBUTION_MODE:-}"
asc_key_path="${PRIVATE_PINYIN_IOS_ASC_KEY_PATH:-}"
asc_key_id="${PRIVATE_PINYIN_IOS_ASC_KEY_ID:-}"
asc_issuer_id="${PRIVATE_PINYIN_IOS_ASC_ISSUER_ID:-}"
project="$repo_root/platform/ios_keyboard/PrivatePinyin.xcodeproj"
archive_path="$repo_root/dist/ios/PrivatePinyin.xcarchive"
export_path="$repo_root/dist/ios/export"
derived_data="$repo_root/build/ios_keyboard_release"
summary_path="$repo_root/dist/ios/package_summary.txt"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

plist_value_or_empty() {
  plist_value "$1" "$2" 2>/dev/null || true
}

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

if ! plutil -lint "$export_options" >/dev/null; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS is not a valid plist: $export_options" >&2
  exit 1
fi

export_method="$(plist_value_or_empty "$export_options" "method")"
if [ "$export_method" != "app-store-connect" ]; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS method must be 'app-store-connect'." >&2
  exit 1
fi

export_destination="$(plist_value_or_empty "$export_options" "destination")"
if [ -z "$export_destination" ]; then
  export_destination="export"
fi

case "$export_destination" in
  export|upload) ;;
  *)
    echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS destination must be 'export' or 'upload'." >&2
    exit 1
    ;;
esac

if [ -n "$distribution_mode" ] && [ "$distribution_mode" != "$export_destination" ]; then
  echo "PRIVATE_PINYIN_IOS_DISTRIBUTION_MODE must match ExportOptions destination '$export_destination'." >&2
  exit 1
fi
distribution_mode="$export_destination"

if [ "$(plist_value_or_empty "$export_options" "teamID")" != "$team_id" ]; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must include teamID '$team_id'." >&2
  exit 1
fi

if [ -z "$(plist_value_or_empty "$export_options" "provisioningProfiles:$app_bundle_id")" ]; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must include provisioning profile for app bundle '$app_bundle_id'." >&2
  exit 1
fi

if [ -z "$(plist_value_or_empty "$export_options" "provisioningProfiles:$keyboard_bundle_id")" ]; then
  echo "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must include provisioning profile for keyboard bundle '$keyboard_bundle_id'." >&2
  exit 1
fi

auth_args=()
if [ -n "$asc_key_path" ] || [ -n "$asc_key_id" ] || [ -n "$asc_issuer_id" ]; then
  if [ -z "$asc_key_path" ] || [ -z "$asc_key_id" ] || [ -z "$asc_issuer_id" ]; then
    echo "PRIVATE_PINYIN_IOS_ASC_KEY_PATH, PRIVATE_PINYIN_IOS_ASC_KEY_ID, and PRIVATE_PINYIN_IOS_ASC_ISSUER_ID must be set together." >&2
    exit 1
  fi
  if [ ! -f "$asc_key_path" ]; then
    echo "PRIVATE_PINYIN_IOS_ASC_KEY_PATH does not exist: $asc_key_path" >&2
    exit 1
  fi
  auth_args=(
    -authenticationKeyPath "$asc_key_path"
    -authenticationKeyID "$asc_key_id"
    -authenticationKeyIssuerID "$asc_issuer_id"
  )
fi

if [ "$distribution_mode" = "upload" ] && [ "${#auth_args[@]}" -eq 0 ]; then
  echo "App Store Connect upload requires PRIVATE_PINYIN_IOS_ASC_KEY_PATH, PRIVATE_PINYIN_IOS_ASC_KEY_ID, and PRIVATE_PINYIN_IOS_ASC_ISSUER_ID." >&2
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
  "${auth_args[@]}" \
  clean archive

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$export_path" \
  "${auth_args[@]}"

cat > "$summary_path" <<EOF
PrivatePinyin iOS package summary

mode: $distribution_mode
archive: $archive_path
export_path: $export_path
export_options: $export_options
team_id: $team_id
app_bundle_id: $app_bundle_id
keyboard_bundle_id: $keyboard_bundle_id
app_group_id: $app_group_id
rust_target: $rust_target
sdk: $sdk
configuration: $configuration
deployment_target: $deployment_target
app_store_connect_api_key: $([ "${#auth_args[@]}" -gt 0 ] && echo configured || echo not_configured)
EOF

echo "Built iOS archive: $archive_path"
if [ "$distribution_mode" = "upload" ]; then
  echo "Uploaded archive through xcodebuild -exportArchive with destination=upload."
else
  echo "Exported iOS artifact to: $export_path"
fi
echo "Wrote package summary: $summary_path"
