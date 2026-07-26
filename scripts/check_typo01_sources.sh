#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ai/local_ai_core/assets/pinyin_corrections.tsv"
  "ime_core/src/pinyin_correction.rs"
  "ime_core/src/candidate.rs"
  "ime_core/tests/candidate_tests.rs"
  "docs/DECISIONS.md"
  "docs/DEVELOPMENT_PROGRESS.md"
  "docs/platform_smoke_test_plan.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required TYPO-01 file: $file" >&2
    exit 1
  fi
done

grep -q 'MAX_PINYIN_CORRECTIONS: usize = 2' ime_core/src/pinyin_correction.rs
grep -q 'MAX_TYPO_INPUT_CHARS: usize = 24' ime_core/src/pinyin_correction.rs
grep -q 'pinyin_corrections.tsv' ime_core/src/pinyin_correction.rs
grep -q 'CandidateCorrectionConfidence::Exact' ime_core/src/pinyin_correction.rs
grep -q 'CandidateCorrectionConfidence::Probable' ime_core/src/pinyin_correction.rs
grep -q 'CandidateCorrectionConfidence::Weak' ime_core/src/pinyin_correction.rs
grep -q 'add_correction_candidates' ime_core/src/session.rs
grep -q 'add_correction_candidates' ime_core/src/api.rs
grep -q 'map_or(0, CandidateCorrection::ai_lite_score)' \
  ffi/ime_ffi/src/local_ai.rs
grep -q 'full_keyboard_typo_correction_preserves_every_original_candidate_path' \
  ime_core/tests/candidate_tests.rs
grep -q 'valid_full_pinyin_and_nine_key_results_are_unchanged_when_correction_is_enabled' \
  ime_core/tests/candidate_tests.rs
grep -q 'full_keyboard_typo_correction_stays_within_interactive_lookup_budget' \
  ime_core/tests/candidate_tests.rs
grep -q 'Decision 045: Bounded Full-Keyboard Typo Candidates Before Nine-Key Correction' \
  docs/DECISIONS.md
grep -q 'NINEKEY-TYPO-01' docs/OPEN_ITEMS.md

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' \
  ime_core/src/pinyin_correction.rs; then
  echo "TYPO-01 must not log composition or corrected candidate content." >&2
  exit 1
fi

echo "TYPO-01 full-keyboard correction source contract passed."
