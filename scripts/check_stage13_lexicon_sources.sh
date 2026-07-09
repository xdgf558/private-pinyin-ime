#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "ime_core/assets/base_lexicon.tsv"
  "ime_core/assets/bigram.tsv"
  "ime_core/assets/lexicon_manifest.json"
  "tools/lexicon_builder/Cargo.toml"
  "tools/lexicon_builder/src/main.rs"
  "docs/lexicon_data_policy.md"
  "THIRD_PARTY_NOTICES.md"
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
grep -q "pinyin-data" tools/lexicon_builder/src/main.rs
grep -q "aosp-rawdict" tools/lexicon_builder/src/main.rs
grep -q "supplemental_pinyin_data" tools/lexicon_builder/src/main.rs
grep -q "release_approved" tools/lexicon_builder/src/main.rs
grep -q "AOSP PinyinIME rawdict" docs/lexicon_data_policy.md
grep -q "pinyin-data" docs/lexicon_data_policy.md
grep -q "OI-001.*closed" docs/lexicon_data_policy.md
grep -q "base_lexicon.tsv" ime_core/assets/lexicon_manifest.json
grep -q "bigram.tsv" ime_core/assets/lexicon_manifest.json
grep -q '"release_approved": true' ime_core/assets/lexicon_manifest.json
grep -q "Apache-2.0" ime_core/assets/lexicon_manifest.json
grep -q "MIT" ime_core/assets/lexicon_manifest.json
grep -q "Android Open Source Project" THIRD_PARTY_NOTICES.md
grep -q "mozillazg" THIRD_PARTY_NOTICES.md
grep -q $'^干嘛\tgan ma\t' ime_core/assets/base_lexicon.tsv
grep -q $'^概率\tgai lü\t' ime_core/assets/base_lexicon.tsv

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

cat >"$tmp_dir/pinyin-data.txt" <<'DATA'
U+884C: xíng,háng  # 行
DATA
cat >"$tmp_dir/char-frequency.tsv" <<'DATA'
character	frequency
行	42
DATA

cargo run -q -p private_pinyin_lexicon -- build-base \
  --format pinyin-data \
  --input "$tmp_dir/pinyin-data.txt" \
  --output "$tmp_dir/pinyin-data-base.tsv" \
  --manifest "$tmp_dir/pinyin-data-manifest.json" \
  --source-name "pinyin-data smoke" \
  --source-license "MIT" \
  --source-version "stage13-check" \
  --char-frequency-input "$tmp_dir/char-frequency.tsv"

grep -q $'^行\thang\t42' "$tmp_dir/pinyin-data-base.tsv"
grep -q $'^行\txing\t42' "$tmp_dir/pinyin-data-base.tsv"

cat >"$tmp_dir/aosp-rawdict.txt" <<'DATA'
干嘛 17002.7639686 0 gan ma
DATA

cargo run -q -p private_pinyin_lexicon -- build-base \
  --format aosp-rawdict \
  --input "$tmp_dir/aosp-rawdict.txt" \
  --output "$tmp_dir/aosp-base.tsv" \
  --manifest "$tmp_dir/aosp-manifest.json" \
  --source-name "AOSP rawdict smoke" \
  --source-license "Apache-2.0" \
  --source-version "stage13-check" \
  --frequency-scale 10 \
  --release-approved

grep -q $'^干嘛\tgan ma\t170028' "$tmp_dir/aosp-base.tsv"
grep -q '"release_approved": true' "$tmp_dir/aosp-manifest.json"

echo "Stage 13 lexicon scaffold checks passed."
