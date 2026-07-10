#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

app_bundle_id="${PRIVATE_PINYIN_IOS_APP_BUNDLE_ID:-com.privatepinyin.ios}"
keyboard_bundle_id="${PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID:-com.privatepinyin.ios.keyboard}"
app_group_id="${PRIVATE_PINYIN_IOS_APP_GROUP_ID:-group.com.privatepinyin.ios}"
derived_data="${PRIVATE_PINYIN_IOS_DERIVED_DATA:-$repo_root/build/ios_keyboard}"
product_dir="$derived_data/Build/Products/Debug-iphonesimulator"
app_path="$product_dir/PrivatePinyin.app"
extension_path="$app_path/PlugIns/PrivatePinyinKeyboard.appex"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

assert_equals() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" != "$expected" ]; then
    echo "$label mismatch: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_exists() {
  if [ ! -e "$1" ]; then
    echo "Missing expected build artifact: $1" >&2
    exit 1
  fi
}

require_command bash
require_command cargo
require_command xcodebuild
require_command plutil
require_command /usr/libexec/PlistBuddy

bash scripts/check_ios_keyboard_sources.sh
bash scripts/check_stage14_ios_signing_sources.sh
bash scripts/build_ios_keyboard.sh

assert_exists "$app_path"
assert_exists "$extension_path"
assert_exists "$app_path/Info.plist"
assert_exists "$extension_path/Info.plist"
assert_exists "$app_path/default_settings.json"
assert_exists "$extension_path/default_settings.json"

assert_equals "Container app bundle identifier" \
  "$app_bundle_id" \
  "$(plist_value "$app_path/Info.plist" "CFBundleIdentifier")"

assert_equals "Keyboard extension bundle identifier" \
  "$keyboard_bundle_id" \
  "$(plist_value "$extension_path/Info.plist" "CFBundleIdentifier")"

assert_equals "Container app display name" \
  "猫栈拼音" \
  "$(plist_value "$app_path/Info.plist" "CFBundleDisplayName")"

assert_equals "Keyboard extension display name" \
  "猫栈拼音" \
  "$(plist_value "$extension_path/Info.plist" "CFBundleDisplayName")"

assert_equals "Container app App Group identifier" \
  "$app_group_id" \
  "$(plist_value "$app_path/Info.plist" "PrivatePinyinAppGroupIdentifier")"

assert_equals "Keyboard extension App Group identifier" \
  "$app_group_id" \
  "$(plist_value "$extension_path/Info.plist" "PrivatePinyinAppGroupIdentifier")"

requests_open_access="$(plist_value "$extension_path/Info.plist" "NSExtension:NSExtensionAttributes:RequestsOpenAccess")"
assert_equals "Keyboard RequestsOpenAccess" "false" "$requests_open_access"

primary_language="$(plist_value "$extension_path/Info.plist" "NSExtension:NSExtensionAttributes:PrimaryLanguage")"
assert_equals "Keyboard primary language" "zh-Hans" "$primary_language"

network_pattern="URLSession|NWConnection|Network.framework|http://|https://"
if command -v rg >/dev/null 2>&1; then
  if rg -n "$network_pattern" \
    --glob "*.swift" \
    platform/ios_keyboard/KeyboardExtension; then
    echo "iOS keyboard extension sources must not include network APIs or URLs." >&2
    exit 1
  fi
else
  found_network_api=0
  while IFS= read -r -d '' swift_file; do
    if grep -nE "$network_pattern" "$swift_file"; then
      found_network_api=1
    fi
  done < <(find platform/ios_keyboard/KeyboardExtension -name "*.swift" -print0)

  if [ "$found_network_api" -eq 1 ]; then
    echo "iOS keyboard extension sources must not include network APIs or URLs." >&2
    exit 1
  fi
fi

cat <<EOF
iOS smoke readiness checks passed.

Container app: $app_path
Keyboard extension: $extension_path
App bundle ID: $app_bundle_id
Keyboard bundle ID: $keyboard_bundle_id
App Group ID: $app_group_id
RequestsOpenAccess: false

Manual smoke still required:
- Tap 打开系统设置 and verify the public Settings entry opens.
- Add 猫栈拼音 and verify that exact Chinese name appears in the keyboard list.
- Verify Notes composition: nihao -> 你好.
- Verify prediction retention: jintian -> 今天 keeps 天气.
- Verify password and phone-number fields fall back to system keyboard.
EOF
