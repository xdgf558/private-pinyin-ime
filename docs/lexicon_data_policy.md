# Lexicon Data Policy

PrivatePinyin may only ship lexicon, phrase frequency, and n-gram data with a clearly documented source and license.

## Required Manifest Fields

Every bundled lexicon-like asset must be listed in `ime_core/assets/lexicon_manifest.json` with:

- `file`
- `source`
- `license`
- `entry_count`

The manifest source must say whether the data is handwritten, generated from project-owned material, or derived from a third-party dataset.

## Production Data Rules

- Do not copy entries from third-party IME dictionaries unless the project owner has approved a compatible license.
- Do not place third-party sample data into this all-rights-reserved repository without recording the exact upstream project, version, license, and transformation steps.
- Keep generated production dictionaries outside runtime-writable directories.
- Treat phrase text, pinyin, frequencies, and bigrams as data with their own licensing requirements.

## Current Stage 09 Status

The bundled sample files are still handwritten project-internal data for development. Stage 09 hardens the ingestion, lookup, ranking, paging, punctuation, and logging paths so a licensed production dictionary can be swapped in later, but it does not replace the sample lexicon with third-party data.
