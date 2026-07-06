#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
source_app="${1:-$repo_root/dist/macos_imk/PrivatePinyin.app}"
destination_dir="$HOME/Library/Input Methods"
destination_app="$destination_dir/PrivatePinyin.app"

if [[ ! -d "$source_app" ]]; then
  echo "Missing app bundle: $source_app" >&2
  echo "Run: bash scripts/build_macos_imk.sh" >&2
  exit 1
fi

mkdir -p "$destination_dir"
rm -rf "$destination_app"
cp -R "$source_app" "$destination_app"

echo "Installed $destination_app"
echo "Open System Settings > Keyboard > Input Sources and add PrivatePinyin."
