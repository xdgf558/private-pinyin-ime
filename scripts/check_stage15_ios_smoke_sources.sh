#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "docs/ios_keyboard_smoke_record.md"
  "docs/platform_smoke_test_plan.md"
  "scripts/run_ios_smoke_readiness.sh"
  "scripts/check_stage15_ios_smoke_sources.sh"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

bash -n scripts/run_ios_smoke_readiness.sh

grep -q "scripts/build_ios_keyboard.sh" scripts/run_ios_smoke_readiness.sh
grep -q "check_ios_keyboard_sources.sh" scripts/run_ios_smoke_readiness.sh
grep -q "check_stage14_ios_signing_sources.sh" scripts/run_ios_smoke_readiness.sh
grep -q "RequestsOpenAccess" scripts/run_ios_smoke_readiness.sh
grep -q "PrivatePinyinAppGroupIdentifier" scripts/run_ios_smoke_readiness.sh
grep -q "PrimaryLanguage" scripts/run_ios_smoke_readiness.sh
grep -q "default_settings.json" scripts/run_ios_smoke_readiness.sh
grep -q "platform/ios_keyboard/KeyboardExtension" scripts/run_ios_smoke_readiness.sh
grep -q "keyboard extension sources must not include network APIs" scripts/run_ios_smoke_readiness.sh
grep -q "Manual smoke still required" scripts/run_ios_smoke_readiness.sh

if grep -q "platform/ios_keyboard/ContainerApp.*network_pattern\\|network_pattern.*platform/ios_keyboard/ContainerApp" scripts/run_ios_smoke_readiness.sh; then
  echo "Stage 15 network scan must not block future ContainerApp URLs." >&2
  exit 1
fi

grep -q "Stage 15" docs/ios_keyboard_smoke_record.md
grep -q "Automated Readiness" docs/ios_keyboard_smoke_record.md
grep -q "Manual Smoke Checklist" docs/ios_keyboard_smoke_record.md
grep -q "Notes composition" docs/ios_keyboard_smoke_record.md
grep -q "Prediction retention" docs/ios_keyboard_smoke_record.md
grep -q "Password fallback" docs/ios_keyboard_smoke_record.md
grep -q "App Group storage" docs/ios_keyboard_smoke_record.md

grep -q "run_ios_smoke_readiness.sh" docs/platform_smoke_test_plan.md

echo "Stage 15 iOS smoke readiness source checks passed."
