#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

version="${PRIVATE_PINYIN_VERSION:-0.1.7}"
app_dir="$repo_root/dist/macos_imk/PrivatePinyin.app"
pkg_root="$repo_root/build/macos_pkg/root"
pkg_scripts_dir="$repo_root/build/macos_pkg/scripts"
unsigned_pkg_path="$repo_root/dist/macos_imk/PrivatePinyin-${version}-unsigned.pkg"
pkg_path="$repo_root/dist/macos_imk/PrivatePinyin-${version}.pkg"
install_dir="$pkg_root/Library/Input Methods"
installer_identity="${PRIVATE_PINYIN_MAC_INSTALLER_SIGN_IDENTITY:-}"
notary_profile="${PRIVATE_PINYIN_NOTARY_PROFILE:-}"
skip_notarization="${PRIVATE_PINYIN_SKIP_NOTARIZATION:-0}"

if ! command -v pkgbuild >/dev/null 2>&1; then
  echo "pkgbuild is required. Install Xcode command line tools first." >&2
  exit 1
fi

if [ -n "$installer_identity" ] && ! command -v productsign >/dev/null 2>&1; then
  echo "productsign is required when PRIVATE_PINYIN_MAC_INSTALLER_SIGN_IDENTITY is set." >&2
  exit 1
fi

if [ -n "$notary_profile" ] && [ "$skip_notarization" != "1" ] && ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required when PRIVATE_PINYIN_NOTARY_PROFILE is set." >&2
  exit 1
fi

bash "$repo_root/scripts/build_macos_imk.sh"

rm -rf "$pkg_root" "$pkg_scripts_dir" "$pkg_path" "$unsigned_pkg_path"
mkdir -p "$install_dir" "$pkg_scripts_dir"
cp -R "$app_dir" "$install_dir/PrivatePinyin.app"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$pkg_root" || true
fi

cat > "$pkg_scripts_dir/postinstall" <<'POSTINSTALL'
#!/bin/sh
set -eu

app_path="/Library/Input Methods/PrivatePinyin.app"
console_user="$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"

if [ -z "$console_user" ] || [ "$console_user" = "root" ] || [ "$console_user" = "loginwindow" ]; then
  exit 0
fi

console_uid="$(/usr/bin/id -u "$console_user" 2>/dev/null || true)"
if [ -z "$console_uid" ]; then
  exit 0
fi

/bin/launchctl asuser "$console_uid" \
  /usr/bin/sudo -u "$console_user" \
  /usr/bin/open "$app_path" --args --show-onboarding >/dev/null 2>&1 || true

exit 0
POSTINSTALL
chmod 755 "$pkg_scripts_dir/postinstall"

pkgbuild \
  --root "$pkg_root" \
  --scripts "$pkg_scripts_dir" \
  --identifier "com.privatepinyin.inputmethod.pkg" \
  --version "$version" \
  --install-location "/" \
  "$unsigned_pkg_path"

if [ -n "$installer_identity" ]; then
  productsign --sign "$installer_identity" "$unsigned_pkg_path" "$pkg_path"
  rm -f "$unsigned_pkg_path"
else
  mv "$unsigned_pkg_path" "$pkg_path"
  echo "Built unsigned package for local testing only."
fi

if [ -n "$notary_profile" ] && [ "$skip_notarization" != "1" ]; then
  xcrun notarytool submit "$pkg_path" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$pkg_path"
fi

echo "Built $pkg_path"
echo "Install with: sudo installer -pkg \"$pkg_path\" -target /"
echo "Then open System Settings > Keyboard > Input Sources and add 猫栈拼音."
