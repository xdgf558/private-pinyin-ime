# Lexicon Data Policy

PrivatePinyin may only ship lexicon, phrase frequency, and n-gram data with a clearly documented source and license.

## Required Manifest Fields

Every bundled lexicon-like asset must be listed in `ime_core/assets/lexicon_manifest.json` with:

- `file`
- `source`
- `license`
- `entry_count`

The manifest source must say whether the data is handwritten, generated from project-owned material, or derived from a third-party dataset. Active release assets must also record whether the data is approved for public release packaging.

## Production Data Rules

- Do not copy entries from third-party IME dictionaries unless the project owner has approved a compatible license.
- Do not place third-party sample data into this all-rights-reserved repository without recording the exact upstream project, version, license, and transformation steps.
- Keep generated production dictionaries outside runtime-writable directories.
- Treat phrase text, pinyin, frequencies, and bigrams as data with their own licensing requirements.
- Do not mark imported data as release-approved until the owner has accepted the upstream license terms and any attribution/share-alike obligations.
- Keep `THIRD_PARTY_NOTICES.md` aligned with any bundled third-party lexicon data.

## Stage 13 Import Tooling

Stage 13 adds `tools/lexicon_builder`, a local conversion and validation tool for building a standard base lexicon TSV plus an audit manifest. The tool supports:

- `private-pinyin-tsv`: the project-native `phrase<TAB>pinyin<TAB>frequency` format.
- `cc-cedict`: local CC-CEDICT style files with numbered pinyin converted to tone-less pinyin for validation.
- `pinyin-data`: mozillazg/pinyin-data style `U+XXXX: pinyin,pinyin # character` lines. Marked pinyin is normalized to tone-less pinyin and can be weighted by an optional character-frequency TSV.
- `aosp-rawdict`: Android Open Source Project PinyinIME raw dictionary lines. UTF-16 rawdict files are decoded, floating-point frequencies are scaled into `u32`, and validated entries are emitted as base-lexicon rows.

The tool does not download third-party data. It only converts local files supplied by the maintainer, writes a generated manifest, and leaves `release_approved` false unless the caller explicitly passes the approval flag.

## Current Stage 13 Status

The active `base_lexicon.tsv` is generated from owner-approved AOSP PinyinIME rawdict data, supplemented with mozillazg pinyin-data single-character readings and first-party common-word fixes for high-value gaps such as `gailv -> 概率`. The active base lexicon has 100,669 entries and includes phrase coverage such as `ganma -> 干嘛`.

The active `bigram.tsv` remains first-party starter data. If future releases replace or expand bigram data from a third-party source, the same manifest, notice, and owner-approval rules apply.

`OI-001` is closed for the current bundled base lexicon because the owner selected AOSP PinyinIME rawdict plus pinyin-data, accepted their Apache-2.0/MIT terms, recorded exact source revisions, and generated the manifest with release approval. The final project license, code signing, notarization, provisioning, and platform smoke evidence remain separate release gates.
