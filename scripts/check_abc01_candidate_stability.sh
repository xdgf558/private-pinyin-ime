#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rg >/dev/null 2>&1; then
  echo "ABC-01 source contract requires ripgrep (rg)." >&2
  exit 1
fi

required_files=(
  "ime_core/src/candidate_stability.rs"
  "ime_core/tests/candidate_tests.rs"
  "ffi/ime_ffi/src/local_ai.rs"
  "docs/DECISIONS.md"
  "docs/DEVELOPMENT_PROGRESS.md"
  "docs/platform_smoke_test_plan.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required ABC-01 file: $file" >&2
    exit 1
  fi
done

grep -q 'STABLE_DEFAULT_CANDIDATE_COUNT: usize = 1' \
  ime_core/src/candidate_stability.rs
grep -q 'pub fn stabilize_candidate_page_order' \
  ime_core/src/candidate_stability.rs
grep -q 'stabilize_candidate_page_order(candidate_texts.len(), &order)' \
  ffi/ime_ffi/src/local_ai.rs
grep -q 'reversed_ai_order_cannot_change_the_default_candidate_commit' \
  ffi/ime_ffi/src/local_ai.rs
grep -q 'same_full_keyboard_composition_replays_identical_candidate_identities' \
  ime_core/tests/candidate_tests.rs
grep -q 'paging_preserves_candidate_identities_and_commits_the_visible_selection' \
  ime_core/tests/candidate_tests.rs
grep -q 'Decision 047: Stable Default Candidate Identity' docs/DECISIONS.md
grep -q '| OI-050 | ABC-01 .*| closed |' docs/OPEN_ITEMS.md
grep -q '| ABC-01 default stability |' docs/platform_smoke_test_plan.md

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' \
  ime_core/src/candidate_stability.rs; then
  echo "ABC-01 must not log candidate identities or input content." >&2
  exit 1
fi

echo "ABC-01 candidate stability source contract passed."
