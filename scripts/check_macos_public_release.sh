#!/usr/bin/env bash
set -u -o pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

version="${PRIVATE_PINYIN_VERSION:-$(awk -F '"' '/^version = / { print $2; exit }' Cargo.toml)}"
pkg_path="${PRIVATE_PINYIN_MAC_PKG_PATH:-$repo_root/dist/macos_imk/PrivatePinyin-${version}.pkg}"
notary_profile="${PRIVATE_PINYIN_NOTARY_PROFILE:-private-pinyin-notary}"
app_identity="${PRIVATE_PINYIN_MAC_APP_SIGN_IDENTITY:-Developer ID Application}"
installer_identity="${PRIVATE_PINYIN_MAC_INSTALLER_SIGN_IDENTITY:-Developer ID Installer}"
failures=0

pass() {
  printf "PASS: %s\n" "$1"
}

fail() {
  printf "FAIL: %s\n" "$1" >&2
  failures=$((failures + 1))
}

info() {
  printf "INFO: %s\n" "$1"
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$1 is available"
  else
    fail "$1 is required for macOS public release validation"
  fi
}

check_codesigning_identity() {
  local label="$1"
  local pattern="$2"
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if printf "%s\n" "$identities" | grep -Fq "$pattern"; then
    pass "$label signing identity is available"
  else
    fail "$label signing identity is missing or does not match: $pattern"
  fi
}

check_identity() {
  local label="$1"
  local pattern="$2"
  local identities
  identities="$(security find-identity -v 2>/dev/null || true)"
  if printf "%s\n" "$identities" | grep -Fq "$pattern"; then
    pass "$label signing identity is available"
  else
    fail "$label signing identity is missing or does not match: $pattern"
  fi
}

capture_check() {
  local label="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    pass "$label"
    if [ -n "$output" ]; then
      printf "%s\n" "$output"
    fi
  else
    fail "$label"
    if [ -n "$output" ]; then
      printf "%s\n" "$output" >&2
    fi
  fi
}

info "Checking macOS public release artifact: $pkg_path"
info "Expected version: $version"

require_command security
require_command pkgutil
require_command spctl
require_command xcrun
require_command shasum

check_codesigning_identity "Developer ID Application" "$app_identity"
check_identity "Developer ID Installer" "$installer_identity"

if [ -f "$pkg_path" ]; then
  pass "package exists"
else
  fail "package does not exist: $pkg_path"
fi

if [ -f "$pkg_path" ]; then
  pkg_signature="$(pkgutil --check-signature "$pkg_path" 2>&1 || true)"
  if printf "%s\n" "$pkg_signature" | grep -q "Status: signed"; then
    pass "package has a trusted installer signature"
  else
    fail "package is not signed with a trusted Developer ID Installer certificate"
  fi
  printf "%s\n" "$pkg_signature"

  capture_check "Gatekeeper accepts the installer package" \
    spctl --assess --type install --verbose=4 "$pkg_path"

  capture_check "notarization ticket is stapled to the package" \
    xcrun stapler validate "$pkg_path"

  checksum="$(shasum -a 256 "$pkg_path" | awk '{ print $1 }')"
  info "SHA256 $checksum"
fi

capture_check "notarytool keychain profile is usable: $notary_profile" \
  xcrun notarytool history --keychain-profile "$notary_profile"

if [ "$failures" -eq 0 ]; then
  echo "macOS public release readiness: passed"
  exit 0
fi

echo "macOS public release readiness: failed with $failures issue(s)" >&2
exit 1
