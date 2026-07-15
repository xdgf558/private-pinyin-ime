#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  ".github/workflows/rust.yml"
  "docs/platform_smoke_test_plan.md"
  "scripts/build_windows_tsf.ps1"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

grep -q "windows-2022" .github/workflows/rust.yml
grep -q "Swatinem/rust-cache@v2" .github/workflows/rust.yml
grep -q "Run Windows Rust tests" .github/workflows/rust.yml
grep -q "cargo test --workspace" .github/workflows/rust.yml
grep -q "Build Windows TSF host" .github/workflows/rust.yml
grep -q "scripts\\\\build_windows_tsf.ps1" .github/workflows/rust.yml
grep -q "PrivatePinyinTsf.dll" scripts/build_windows_tsf.ps1

grep -q "Windows 11 TSF Smoke" docs/platform_smoke_test_plan.md
grep -q "macOS InputMethodKit Smoke" docs/platform_smoke_test_plan.md
grep -q "iOS Keyboard Smoke" docs/platform_smoke_test_plan.md
grep -q "Ctrl+C" docs/platform_smoke_test_plan.md
grep -q "Focus cleanup" docs/platform_smoke_test_plan.md
grep -q "Multi-process learning" docs/platform_smoke_test_plan.md
grep -q "App switch cleanup" docs/platform_smoke_test_plan.md
grep -q "Number-key selection" docs/platform_smoke_test_plan.md
grep -q "Input source discovery" docs/platform_smoke_test_plan.md
grep -q "Post-install onboarding" docs/platform_smoke_test_plan.md
grep -q "Upgrade process detection" docs/platform_smoke_test_plan.md
grep -q "Consecutive upgrade" docs/platform_smoke_test_plan.md
grep -q "jintian -> 今天" docs/platform_smoke_test_plan.md
grep -q "textDidChange" docs/platform_smoke_test_plan.md
