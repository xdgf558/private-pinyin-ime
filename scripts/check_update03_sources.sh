#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "docs/macos_update_strategy.md"
  "platform/macos_imk/Sources/PrivatePinyinProcessRefreshPolicy.swift"
  "platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift"
  "platform/macos_imk/Tests/ProcessRefreshPolicyTests.swift"
  "scripts/test_macos_process_refresh.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required UPDATE-03 file: $file" >&2
    exit 1
  fi
done

grep -q 'runningApplications(withBundleIdentifier: bundleIdentifier)' \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift
grep -q 'application.processIdentifier' \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift
grep -q 'application.launchDate' \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift
grep -q 'eligibleProcessIdentifiers' \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift
grep -q 'application.terminate()' \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift
grep -q '不会关闭浏览器、编辑器或其他应用' \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift
grep -q '请注销并重新登录' \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift
grep -q '无需先重启电脑' \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift
grep -q -- '--post-install-follow-up' \
  platform/macos_imk/Sources/PrivatePinyinProcessRefreshPolicy.swift
grep -q 'isUIOnlyHelper' platform/macos_imk/Sources/main.swift
grep -q 'app_executable="$app_path/Contents/MacOS/PrivatePinyin"' scripts/package_macos_pkg.sh
grep -q '/usr/bin/nohup "$app_executable"' scripts/package_macos_pkg.sh
grep -q -- '--post-install-follow-up --installed-at "$installed_at"' scripts/package_macos_pkg.sh
grep -q '/bin/date +%s.%N' scripts/package_macos_pkg.sh
grep -q 'launchDate < installedAt' \
  platform/macos_imk/Sources/PrivatePinyinProcessRefreshPolicy.swift
grep -q 'now.addingTimeInterval(0.5)' \
  platform/macos_imk/Tests/ProcessRefreshPolicyTests.swift
grep -q 'PRIVATE_PINYIN_REQUIRE_SWIFTC' scripts/test_macos_process_refresh.sh
grep -q 'PrivatePinyinProcessRefreshPolicy.swift' scripts/build_macos_imk.sh
grep -q 'PrivatePinyinPostInstallController.swift' scripts/build_macos_imk.sh
grep -q 'No unrelated application is terminated' docs/macos_update_strategy.md

if grep -R -E -q 'forceTerminate\(|killall|pkill|/bin/kill|/sbin/shutdown|osascript' \
  platform/macos_imk/Sources/PrivatePinyinProcessRefreshPolicy.swift \
  platform/macos_imk/Sources/PrivatePinyinPostInstallController.swift \
  scripts/package_macos_pkg.sh; then
  echo "UPDATE-03 must not force-terminate processes, log out, or restart macOS" >&2
  exit 1
fi

bash scripts/test_macos_process_refresh.sh

echo "UPDATE-03 source checks passed."
