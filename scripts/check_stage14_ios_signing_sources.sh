#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "platform/ios_keyboard/AppStoreMetadata/ExportOptions.plist.template"
  "platform/ios_keyboard/AppStoreMetadata/Signing.env.example"
  "platform/ios_keyboard/ContainerApp/Info.plist"
  "platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements"
  "platform/ios_keyboard/KeyboardExtension/Info.plist"
  "platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements"
  "platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj"
  "scripts/package_ios_app_store.sh"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

if command -v plutil >/dev/null 2>&1; then
  plutil -lint platform/ios_keyboard/ContainerApp/Info.plist >/dev/null
  plutil -lint platform/ios_keyboard/KeyboardExtension/Info.plist >/dev/null
  plutil -lint platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements >/dev/null
  plutil -lint platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements >/dev/null
  plutil -lint platform/ios_keyboard/AppStoreMetadata/ExportOptions.plist.template >/dev/null
fi

grep -q "PRIVATE_PINYIN_IOS_TEAM_ID" scripts/package_ios_app_store.sh
grep -q "PRIVATE_PINYIN_IOS_APP_BUNDLE_ID" scripts/package_ios_app_store.sh
grep -q "PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID" scripts/package_ios_app_store.sh
grep -q "PRIVATE_PINYIN_IOS_APP_GROUP_ID" scripts/package_ios_app_store.sh
grep -q "PRIVATE_PINYIN_IOS_APP_BUNDLE_ID" scripts/build_ios_keyboard.sh
grep -q "PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID" scripts/build_ios_keyboard.sh
grep -q "PRIVATE_PINYIN_IOS_APP_GROUP_ID" scripts/build_ios_keyboard.sh
grep -q "must start with 'group.'" scripts/package_ios_app_store.sh
grep -q "PRIVATE_PINYIN_IOS_EXPORT_OPTIONS must include provisioning profile" scripts/package_ios_app_store.sh

grep -q "PRIVATE_PINYIN_IOS_APP_BUNDLE_ID = com.privatepinyin.ios" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID = com.privatepinyin.ios.keyboard" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "PRIVATE_PINYIN_IOS_APP_GROUP_ID = group.com.privatepinyin.ios" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = "$(PRIVATE_PINYIN_IOS_APP_BUNDLE_ID)"' platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = "$(PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID)"' platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj

grep -q "PrivatePinyinAppGroupIdentifier" platform/ios_keyboard/ContainerApp/Info.plist
grep -q "PrivatePinyinAppGroupIdentifier" platform/ios_keyboard/KeyboardExtension/Info.plist
grep -q "\$(PRIVATE_PINYIN_IOS_APP_GROUP_ID)" platform/ios_keyboard/ContainerApp/Info.plist
grep -q "\$(PRIVATE_PINYIN_IOS_APP_GROUP_ID)" platform/ios_keyboard/KeyboardExtension/Info.plist
grep -q "\$(PRIVATE_PINYIN_IOS_APP_GROUP_ID)" platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements
grep -q "\$(PRIVATE_PINYIN_IOS_APP_GROUP_ID)" platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements
grep -q "PrivatePinyinAppGroupIdentifier" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "fallbackAppGroupIdentifier" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift

if grep -q "<string>group.com.privatepinyin.ios</string>" \
  platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements \
  platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements; then
  echo "iOS App Group entitlements must use PRIVATE_PINYIN_IOS_APP_GROUP_ID build setting." >&2
  exit 1
fi

grep -q "PRIVATE_PINYIN_IOS_APP_GROUP_ID" platform/ios_keyboard/AppStoreMetadata/Signing.env.example
grep -q "Signing.env" .gitignore
grep -Fq "platform/ios_keyboard/AppStoreMetadata/ExportOptions*.plist" .gitignore

echo "Stage 14 iOS signing and App Group source checks passed."
