#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rg >/dev/null 2>&1; then
  echo "ABC-03 source contract requires ripgrep (rg)." >&2
  exit 1
fi

required_files=(
  "ime_core/src/ranker.rs"
  "ime_core/src/user_lexicon.rs"
  "ime_core/tests/ranking_tests.rs"
  "ime_core/tests/user_lexicon_tests.rs"
  "ffi/ime_ffi/src/local_ai.rs"
  "docs/DECISIONS.md"
  "docs/DEVELOPMENT_PROGRESS.md"
  "docs/platform_smoke_test_plan.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required ABC-03 file: $file" >&2
    exit 1
  fi
done

grep -q 'USER_LEARNING_CONFIRMATION_WEIGHT: f64 = 3.0' ime_core/src/ranker.rs
grep -q 'effective_user_learning_weight(user_weight)' ime_core/src/ranker.rs
grep -q 'score_user_learning_weight(weight)' ime_core/src/user_lexicon.rs
grep -q 'gentle_learning_keeps_default_stable_until_third_confirmation' \
  ime_core/tests/user_lexicon_tests.rs
grep -q 'gentle_learning_delays_trigram_prediction_until_third_confirmation' \
  ime_core/tests/user_lexicon_tests.rs
grep -q 'decayed_learning_returns_to_warmup_without_deleting_history' \
  ime_core/tests/user_lexicon_tests.rs
grep -q 'warmup_learning_does_not_reach_ai_lite_frequency_or_context_features' \
  ffi/ime_ffi/src/local_ai.rs
grep -q 'Decision 049: Three-Confirmation Gentle Local Learning' docs/DECISIONS.md
grep -q '| OI-052 | ABC-03 .*| closed |' docs/OPEN_ITEMS.md
test "$(grep -c '| ABC-03 gentle learning |' docs/platform_smoke_test_plan.md)" -eq 3

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' \
  ime_core/src/ranker.rs ime_core/src/user_lexicon.rs; then
  echo "ABC-03 must not log user-learning or candidate content." >&2
  exit 1
fi

echo "ABC-03 gentle learning source contract passed."
