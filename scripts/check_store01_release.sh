#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

container_plist="platform/ios_keyboard/ContainerApp/Info.plist"
extension_plist="platform/ios_keyboard/KeyboardExtension/Info.plist"
container_privacy="platform/ios_keyboard/ContainerApp/PrivacyInfo.xcprivacy"
extension_privacy="platform/ios_keyboard/KeyboardExtension/PrivacyInfo.xcprivacy"
metadata_dir="platform/ios_keyboard/AppStoreMetadata"

for plist in "$container_plist" "$extension_plist" "$container_privacy" "$extension_privacy"; do
  plutil -lint "$plist" >/dev/null
done

for plist in "$container_plist" "$extension_plist"; do
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "1.0.0" ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "27" ]
done

for plist in "$container_privacy" "$extension_privacy"; do
  [ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$plist")" = "false" ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyCollectedDataTypes' "$plist" | tr -d '[:space:]')" = "Array{}" ]
  grep -q 'NSPrivacyAccessedAPICategoryUserDefaults' "$plist"
  grep -q 'CA92.1' "$plist"
done
grep -q 'NSPrivacyAccessedAPICategorySystemBootTime' "$extension_privacy"
grep -q '35F9.1' "$extension_privacy"

project="platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj"
[ "$(grep -c 'PrivacyInfo.xcprivacy in Resources' "$project")" -eq 4 ]

for file in \
  store_listing_zh-Hans.md \
  review_notes_zh-Hans.md \
  screenshot_checklist.md \
  privacy_audit.md \
  release_checklist.md; do
  test -s "$metadata_dir/$file"
done

[ "$(/usr/libexec/PlistBuddy -c 'Print :StorePrivacyPolicyURL' "$container_plist")" = \
  "https://wwwstationcat.org/zh-hans/apps/privatepinyin/privacy/" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :StoreSupportURL' "$container_plist")" = \
  "https://wwwstationcat.org/zh-hans/apps/privatepinyin/support/" ]
grep -q 'configuredStoreURL("StorePrivacyPolicyURL")' \
  platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'configuredStoreURL("StoreSupportURL")' \
  platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'RequestsOpenAccess' "$extension_plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:RequestsOpenAccess' "$extension_plist")" = "false" ]

echo "STORE-01 release source checks passed."
