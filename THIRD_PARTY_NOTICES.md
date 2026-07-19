# Third-Party Notices

PrivatePinyin includes generated lexicon data derived from the following upstream sources. These notices apply to the generated data in `ime_core/assets/base_lexicon.tsv`; they do not change the license of original PrivatePinyin source code.

## Android Open Source Project PinyinIME Raw Dictionary

- Component: `rawdict_utf16_65105_freq.txt`
- Upstream: Android Open Source Project `platform/packages/inputmethods/PinyinIME`
- Source URL: https://android.googlesource.com/platform/packages/inputmethods/PinyinIME/+/refs/heads/main/jni/data/rawdict_utf16_65105_freq.txt
- Source revision: `49aebad1c1cfbbcaa9288ffed5161e79e57c3679`
- License: Apache License, Version 2.0
- Notice: Copyright (c) 2009, The Android Open Source Project

## mozillazg pinyin-data

- Component: `pinyin.txt`
- Upstream: `mozillazg/pinyin-data`
- Source URL: https://github.com/mozillazg/pinyin-data/blob/master/pinyin.txt
- Source revision: `923b108dc5d45dee061324c011b478fb649f8b73`
- Source version: `0.15.0`
- License: MIT
- Notice: Copyright (c) 2016 mozillazg

## mozillazg phrase-pinyin-data

- Component: `pinyin.txt`
- Upstream: `mozillazg/phrase-pinyin-data`
- Source URL: https://github.com/mozillazg/phrase-pinyin-data/blob/cee0ed6e6e4898580cafd2bd5e3723e20b214aa0/pinyin.txt
- Source revision: `cee0ed6e6e4898580cafd2bd5e3723e20b214aa0`
- Source version: `0.19.0`
- License: MIT
- Notice: Copyright (c) 2016 mozillazg

## Transformation

`tools/lexicon_builder` generated the bundled base lexicon from the AOSP raw dictionary and supplemented it with pinyin-data single-character readings:

```bash
cargo run -q -p private_pinyin_lexicon -- build-base \
  --format aosp-rawdict \
  --input rawdict_utf16_65105_freq.txt \
  --output ime_core/assets/base_lexicon.tsv \
  --manifest private_pinyin_lexicon_build_manifest.json \
  --source-name "Android Open Source Project PinyinIME rawdict plus mozillazg pinyin-data" \
  --source-license "Apache-2.0 for AOSP rawdict; MIT for pinyin-data" \
  --source-version "AOSP PinyinIME 49aebad1c1cfbbcaa9288ffed5161e79e57c3679; pinyin-data v0.15.0 923b108dc5d45dee061324c011b478fb649f8b73" \
  --frequency-scale 1 \
  --default-frequency 25 \
  --supplemental-pinyin-data pinyin.txt \
  --release-approved
```

The approved base was then supplemented with the MIT `phrase-pinyin-data/pinyin.txt` phrase readings. New supplemental rows use frequency 25 so existing AOSP frequency ordering remains dominant:

```bash
cargo run -q -p private_pinyin_lexicon -- build-base \
  --format private-pinyin-tsv \
  --input ime_core/assets/base_lexicon.tsv \
  --output base_lexicon_with_phrases.tsv \
  --manifest phrase_pinyin_build_manifest.json \
  --source-name "Current approved base plus mozillazg phrase-pinyin-data" \
  --source-license "Apache-2.0/MIT/project-internal; supplemental phrase-pinyin-data MIT" \
  --source-url "https://github.com/mozillazg/phrase-pinyin-data" \
  --source-version "phrase-pinyin-data v0.19.0 cee0ed6e6e4898580cafd2bd5e3723e20b214aa0" \
  --default-frequency 25 \
  --supplemental-phrase-pinyin-data phrase-pinyin-data/pinyin.txt \
  --release-approved
```

Rime dictionaries imported by an end user are not bundled or redistributed by PrivatePinyin. They remain subject to their upstream licenses.
