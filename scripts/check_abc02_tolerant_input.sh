#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rg >/dev/null 2>&1; then
  echo "ABC-02 source contract requires ripgrep (rg)." >&2
  exit 1
fi

required_files=(
  "ime_core/src/tolerant_input.rs"
  "ime_core/src/lexicon.rs"
  "ime_core/src/user_lexicon.rs"
  "ime_core/tests/candidate_tests.rs"
  "platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift"
  "platform/windows_tsf/installer/open-settings.ps1"
  "platform/ios_keyboard/ContainerApp/ContentView.swift"
  "docs/DECISIONS.md"
  "docs/DEVELOPMENT_PROGRESS.md"
  "docs/platform_smoke_test_plan.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required ABC-02 file: $file" >&2
    exit 1
  fi
done

grep -q 'MAX_TOLERANT_INPUT_CHARS: usize = 24' ime_core/src/tolerant_input.rs
grep -q 'MAX_TOLERANT_VARIANTS: usize = 16' ime_core/src/tolerant_input.rs
grep -q 'MAX_TOLERANT_CANDIDATES: usize = 2' ime_core/src/tolerant_input.rs
grep -q 'CandidateCorrectionKind::FuzzyPinyin' ime_core/src/tolerant_input.rs
grep -q 'pub(crate) fn lookup_exact' ime_core/src/lexicon.rs
grep -q 'WHERE pinyin = ?1' ime_core/src/user_lexicon.rs
grep -q 'tolerant_pinyin_preserves_original_order_and_exposes_bounded_low_priority_candidates' \
  ime_core/tests/candidate_tests.rs
grep -q 'tolerant_pinyin_session_commits_without_mutating_the_typed_preedit' \
  ime_core/tests/candidate_tests.rs
grep -q 'tolerant_pinyin_stays_within_interactive_lookup_budget' \
  ime_core/tests/candidate_tests.rs
grep -q '宽容拼音' \
  platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q '宽容拼音' platform/windows_tsf/installer/open-settings.ps1
grep -q '\$script:initialTolerantPinyinEnabled = \[bool\]\$tolerantPinyin.Checked' \
  platform/windows_tsf/installer/open-settings.ps1
grep -q '宽容拼音' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'Decision 048: Bounded Opt-In Syllable-Level Tolerant Pinyin' docs/DECISIONS.md
grep -q '| OI-051 | ABC-02 .*| closed |' docs/OPEN_ITEMS.md
grep -q '| ABC-02 tolerant input |' docs/platform_smoke_test_plan.md

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' ime_core/src/tolerant_input.rs; then
  echo "ABC-02 must not log raw input, alternate spellings, or candidate content." >&2
  exit 1
fi

echo "ABC-02 tolerant input source contract passed."
