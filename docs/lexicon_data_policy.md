# Lexicon Data Policy

PrivatePinyin may only ship lexicon, phrase frequency, and n-gram data with a clearly documented source and license.

## Required Manifest Fields

Every bundled lexicon-like asset must be listed in `ime_core/assets/lexicon_manifest.json` with:

- `file`
- `source`
- `license`
- `entry_count`

The manifest source must say whether the data is handwritten, generated from project-owned material, or derived from a third-party dataset.
Active release assets must also record whether the data is approved for public release packaging.

## Production Data Rules

- Do not copy entries from third-party IME dictionaries unless the project owner has approved a compatible license.
- Do not place third-party sample data into this all-rights-reserved repository without recording the exact upstream project, version, license, and transformation steps.
- Keep generated production dictionaries outside runtime-writable directories.
- Treat phrase text, pinyin, frequencies, and bigrams as data with their own licensing requirements.
- Do not mark imported data as release-approved until the owner has accepted the upstream license terms and any attribution/share-alike obligations.

## Stage 13 Import Tooling

Stage 13 adds `tools/lexicon_builder`, a local conversion and validation tool for building a standard base lexicon TSV plus an audit manifest. The tool supports:

- `private-pinyin-tsv`: the project-native `phrase<TAB>pinyin<TAB>frequency` format.
- `cc-cedict`: local CC-CEDICT style files with numbered pinyin converted to tone-less pinyin for validation.

The tool does not download third-party data. It only converts local files supplied by the maintainer, writes a generated manifest, and leaves `release_approved` false unless the caller explicitly passes the approval flag.

## Current Stage 13 Status

The active `base_lexicon.tsv` and `bigram.tsv` files are first-party starter data so installed builds are no longer limited to the original eight-word development sample. They are not copied from Rime, libpinyin, CC-CEDICT, or any other third-party source. This improves usability for local smoke testing but does not close the production data release gate.

`OI-001` remains open until the owner selects and approves a compatible production lexicon source, records the exact source version, and runs the import tool with release approval for a public release candidate.
