#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "ime_core/assets/base_lexicon.tsv"
  "ime_core/assets/bigram.tsv"
  "ime_core/assets/lexicon_manifest.json"
  "tools/lexicon_builder/Cargo.toml"
  "tools/lexicon_builder/src/main.rs"
  "docs/lexicon_data_policy.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required Stage 13 file: $file" >&2
    exit 1
  fi
done

grep -q "tools/lexicon_builder" Cargo.toml
grep -q "base_lexicon.tsv" ime_core/src/lexicon.rs
grep -q "bigram.tsv" ime_core/src/predictor.rs
grep -q "private-pinyin-lexicon" tools/lexicon_builder/Cargo.toml
grep -q "cc-cedict" tools/lexicon_builder/src/main.rs
grep -q "release_approved" tools/lexicon_builder/src/main.rs
grep -q "first-party starter data" docs/lexicon_data_policy.md
grep -q "base_lexicon.tsv" ime_core/assets/lexicon_manifest.json
grep -q "bigram.tsv" ime_core/assets/lexicon_manifest.json

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cargo run -q -p private_pinyin_lexicon -- build-base \
  --format private-pinyin-tsv \
  --input ime_core/assets/base_lexicon_sample.tsv \
  --output "$tmp_dir/base.tsv" \
  --manifest "$tmp_dir/manifest.json" \
  --source-name "PrivatePinyin sample" \
  --source-license "project-internal sample data" \
  --source-version "stage13-check"

grep -q "你好" "$tmp_dir/base.tsv"
grep -q '"release_approved": false' "$tmp_dir/manifest.json"

echo "Stage 13 lexicon scaffold checks passed."
