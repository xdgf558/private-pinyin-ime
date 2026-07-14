#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "docs/macos_update_strategy.md"
  "platform/macos_imk/Sources/PrivatePinyinUpdateController.swift"
  "platform/macos_imk/Sources/UpdateManifest.swift"
  "platform/macos_imk/Tests/Fixtures/stable-update.json"
  "platform/macos_imk/Tests/UpdateManifestTests.swift"
  "scripts/test_macos_update_manifest.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required UPDATE-01 file: $file" >&2
    exit 1
  fi
done

grep -q 'URLSessionConfiguration.ephemeral' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'configuration.urlCache = nil' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'configuration.httpCookieStorage = nil' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'configuration.httpShouldSetCookies = false' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'PrivatePinyinSettingsStore.isStrictPrivacyModeEnabled' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'cancelBackgroundCheckIfNeeded' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'applyCurrentPrivacyPolicy' platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q 'guard activeCheckID == checkID' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -A3 'var automaticChecksEnabled' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift | grep -q 'return false'
grep -q 'maximumManifestBytes = 128 \* 1024' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'URLSessionDataDelegate' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'data.count <= Self.maximumManifestBytes - receivedData.count' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'url.scheme?.lowercased() == "https"' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'PrivatePinyinUpdateManifestURL' platform/macos_imk/Resources/Info.plist
grep -q 'https://wwwstationcat.org/updates/private-pinyin/macos/stable.json' platform/macos_imk/Resources/Info.plist
grep -q 'PrivatePinyinUpdateAllowedHost' platform/macos_imk/Resources/Info.plist
grep -q 'wwwstationcat.org' platform/macos_imk/Resources/Info.plist
grep -q 'PrivatePinyinUpdateController.shared.menuTitle' platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q '自动检查更新' platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q '可选。每天最多读取一次公开版本清单' platform/macos_imk/Sources/PrivatePinyinOnboardingWindowController.swift
grep -q 'packageSHA256.utf8.count == 64' platform/macos_imk/Sources/UpdateManifest.swift
grep -q 'package.pathExtension.lowercased() == "pkg"' platform/macos_imk/Sources/UpdateManifest.swift
grep -q 'No network request is made by default' docs/macos_update_strategy.md

bash scripts/test_macos_update_manifest.sh

echo "UPDATE-01 source checks passed."
