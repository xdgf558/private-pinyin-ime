#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

version="${PRIVATE_PINYIN_VERSION:-0.1.0}"
app_dir="$repo_root/dist/macos_imk/PrivatePinyin.app"
pkg_root="$repo_root/build/macos_pkg/root"
pkg_path="$repo_root/dist/macos_imk/PrivatePinyin-${version}.pkg"
install_dir="$pkg_root/Library/Input Methods"

if ! command -v pkgbuild >/dev/null 2>&1; then
  echo "pkgbuild is required. Install Xcode command line tools first." >&2
  exit 1
fi

bash "$repo_root/scripts/build_macos_imk.sh"

rm -rf "$pkg_root" "$pkg_path"
mkdir -p "$install_dir"
cp -R "$app_dir" "$install_dir/PrivatePinyin.app"

pkgbuild \
  --root "$pkg_root" \
  --identifier "com.privatepinyin.inputmethod.pkg" \
  --version "$version" \
  --install-location "/" \
  "$pkg_path"

echo "Built $pkg_path"
echo "Install with: sudo installer -pkg \"$pkg_path\" -target /"
echo "Then open System Settings > Keyboard > Input Sources and add PrivatePinyin."
