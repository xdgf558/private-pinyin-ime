#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "docs/lexicon_data_policy.md"
  "ime_core/assets/lexicon_manifest.json"
  "ime_core/src/lexicon.rs"
  "ime_core/src/user_lexicon.rs"
  "ime_core/src/ranker.rs"
  "ime_core/src/session.rs"
  "ime_core/src/logger.rs"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

grep -q "compact_index" ime_core/src/lexicon.rs
grep -q "partition_point" ime_core/src/lexicon.rs
grep -q "compact_pinyin >= ?1 AND compact_pinyin < ?2" ime_core/src/user_lexicon.rs
grep -q "idx_user_phrases_pinyin" ime_core/src/user_lexicon.rs
grep -q "CandidateMatchKind" ime_core/src/ranker.rs
grep -q "turn_candidate_page" ime_core/src/session.rs
grep -q "commit_punctuation" ime_core/src/session.rs
grep -q "emit_error" ime_core/src/session.rs
grep -q "emit_error" ime_core/src/api.rs
grep -q "lexicon_manifest.json" docs/lexicon_data_policy.md
grep -q "OI-001.*closed" docs/lexicon_data_policy.md
