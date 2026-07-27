#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rg >/dev/null 2>&1; then
  echo "NINEKEY-TYPO-01 source contract requires ripgrep (rg)." >&2
  exit 1
fi

required_files=(
  "ime_core/src/nine_key_correction.rs"
  "ime_core/src/lexicon.rs"
  "ime_core/src/candidate.rs"
  "ime_core/tests/candidate_tests.rs"
  "docs/DECISIONS.md"
  "docs/DEVELOPMENT_PROGRESS.md"
  "docs/platform_smoke_test_plan.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required NINEKEY-TYPO-01 file: $file" >&2
    exit 1
  fi
done

grep -q 'MAX_NINE_KEY_CORRECTIONS: usize = 2' ime_core/src/nine_key_correction.rs
grep -q 'MAX_NINE_KEY_TYPO_INPUT_DIGITS: usize = 24' ime_core/src/nine_key_correction.rs
grep -q 'MAX_NINE_KEY_CORRECTION_ATTEMPTS: usize = 64' ime_core/src/nine_key_correction.rs
grep -q 'NineKeyAdjacentDigit' ime_core/src/candidate.rs
grep -q 'NineKeyExtraDigit' ime_core/src/candidate.rs
grep -q 'NineKeyMissingDigit' ime_core/src/candidate.rs
grep -q 'NineKeyTransposedDigits' ime_core/src/candidate.rs
grep -q 'exact_range(corrected_digits)' ime_core/src/lexicon.rs
grep -q 'merge_user_and_base_candidates_with_corrections' ime_core/src/api.rs
grep -q 'lookup_nine_key_with_context_corrected_cached' ime_core/src/session.rs
grep -q 'nine_key_correction_handles_each_bounded_edit_without_reordering_raw_candidates' \
  ime_core/src/lexicon.rs
grep -q 'nine_key_correction_cache_matches_stateless_lookup_after_backspace_and_retype' \
  ime_core/src/lexicon.rs
grep -q 'nine_key_typo_correction_commits_once_without_mutating_digit_preedit' \
  ime_core/tests/candidate_tests.rs
grep -q 'nine_key_incremental_session_stays_within_interactive_lookup_budget' \
  ime_core/tests/candidate_tests.rs
grep -q '拼音智能纠错' \
  platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q '拼音智能纠错' platform/windows_tsf/installer/open-settings.ps1
grep -q '拼音智能纠错' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'Decision 046: Bounded Nine-Key Typo Candidates After Ordinary Decoding' \
  docs/DECISIONS.md
grep -q '| OI-049 | NINEKEY-TYPO-01 .*| closed |' docs/OPEN_ITEMS.md
grep -q '| Nine-key typo correction |' docs/platform_smoke_test_plan.md

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' \
  ime_core/src/nine_key_correction.rs; then
  echo "NINEKEY-TYPO-01 must not log digit signatures or candidate content." >&2
  exit 1
fi

echo "NINEKEY-TYPO-01 source contract passed."
