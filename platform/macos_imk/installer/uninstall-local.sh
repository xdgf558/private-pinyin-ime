#!/usr/bin/env bash
set -euo pipefail

destination_app="$HOME/Library/Input Methods/PrivatePinyin.app"

rm -rf "$destination_app"

echo "Removed $destination_app"
echo "If PrivatePinyin is still listed, remove it from System Settings > Keyboard > Input Sources."
