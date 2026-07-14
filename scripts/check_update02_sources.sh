#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "docs/macos_update_strategy.md"
  "platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift"
  "platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift"
  "platform/macos_imk/Tests/UpdatePackageVerifierTests.swift"
  "scripts/test_macos_update_package.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required UPDATE-02 file: $file" >&2
    exit 1
  fi
done

grep -q 'URLSessionDownloadDelegate' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'URLSessionConfiguration.ephemeral' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'configuration.urlCache = nil' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'configuration.httpCookieStorage = nil' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'configuration.urlCredentialStorage = nil' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'totalBytesWritten > expectedSize' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'totalBytesExpectedToWrite != expectedSize' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'size == expectedSize' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'url.host?.lowercased() == allowedHost' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q 'url.pathExtension.lowercased() == "pkg"' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q '0o700' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift
grep -q '0o600' platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift

grep -q 'import CryptoKit' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'var hasher = SHA256()' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'attributes\[.type\].*typeRegular' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'URL(fileURLWithPath: "/usr/sbin/pkgutil")' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'URL(fileURLWithPath: "/usr/sbin/spctl")' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'process.executableURL = executableURL' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'process.arguments = arguments' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'commandTimeout.*seconds(30)' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'Status: signed by a developer certificate issued by Apple for distribution' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'Developer ID Installer:' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'source=Notarized Developer ID' platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift
grep -q 'PrivatePinyinUpdateExpectedInstallerTeamID' platform/macos_imk/Resources/Info.plist
grep -q 'Y35K7AQ974' platform/macos_imk/Resources/Info.plist

grep -q '下载并验证' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'cancelPackageDownloadIfNeeded' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'case installerHandoff' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'removeItem(at: packageURL)' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q '/System/Library/CoreServices/Installer.app' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'withApplicationAt: installerURL' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q '由你确认并输入系统密码' platform/macos_imk/Sources/PrivatePinyinUpdateController.swift
grep -q 'No silent privileged installation' docs/macos_update_strategy.md

if grep -R -q '/usr/sbin/installer\|/usr/bin/sudo' \
  platform/macos_imk/Sources/PrivatePinyinUpdateController.swift \
  platform/macos_imk/Sources/PrivatePinyinPackageDownloader.swift \
  platform/macos_imk/Sources/PrivatePinyinPackageVerifier.swift; then
  echo "UPDATE-02 must not invoke a privileged installer or sudo" >&2
  exit 1
fi

bash scripts/test_macos_update_package.sh

echo "UPDATE-02 source checks passed."
