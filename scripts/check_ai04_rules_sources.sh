#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ai/local_ai_core/assets/pinyin_corrections.tsv"
  "ai/local_ai_core/assets/english_terms.tsv"
  "ai/local_ai_core/src/rules/mod.rs"
  "ai/local_ai_core/src/rules/pinyin_correction.rs"
  "ai/local_ai_core/src/rules/english_terms.rs"
  "ai/local_ai_core/src/rules/lexicon_cleanup.rs"
  "ai/local_ai_core/src/rules/tests.rs"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required AI-04 file: $file" >&2
    exit 1
  fi
done

grep -q 'MAX_PINYIN_CORRECTIONS: usize = 2' \
  ai/local_ai_core/src/rules/pinyin_correction.rs
grep -q 'suggest_with_validator' ai/local_ai_core/src/rules/pinyin_correction.rs
grep -q 'API key' ai/local_ai_core/assets/english_terms.tsv
grep -q 'MAX_MIXED_INPUT_BYTES: usize = 128' \
  ai/local_ai_core/src/rules/english_terms.rs
grep -q 'MixedInputSegmentKind::EnglishTerm' \
  ai/local_ai_core/src/rules/english_terms.rs
grep -q 'DuplicateNormalizedEntry' ai/local_ai_core/src/rules/lexicon_cleanup.rs
grep -q 'privacy_mode == AiPrivacyMode::Strict' \
  ai/local_ai_core/src/rules/lexicon_cleanup.rs
grep -q 'analysis must never mutate the snapshot' ai/local_ai_core/src/rules/tests.rs
grep -q 'english_term_boundaries_require_surrounding_pinyin_to_decode' \
  ai/local_ai_core/src/rules/tests.rs
grep -q 'rules_first_evaluation_improves_p0_cases_without_required_regression' \
  tools/ai_eval_runner/src/lib.rs

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' ai/local_ai_core/src/rules; then
  echo "AI-04 rules must not log pinyin, terms, or lexicon content." >&2
  exit 1
fi

bash scripts/check_no_external_ai_service.sh
cargo test -p private_pinyin_local_ai_core
cargo run -q -p private_pinyin_ai_eval_runner -- \
  --rules --require-observed-successes 7

echo "AI-04 rules-first checks passed."
