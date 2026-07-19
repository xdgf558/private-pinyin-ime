# Local Rime Lexicon Import

PrivatePinyin ships a reviewed permissive base dictionary for every user. Advanced users can additionally import local Rime YAML dictionaries without replacing that base.

## Storage Model

The three layers are independent:

1. `base_lexicon.tsv`: immutable, bundled, reviewed Apache-2.0/MIT data.
2. `imported_lexicon.tsv`: user-selected local Rime rows; preserved by app upgrades.
3. `user_lexicon.sqlite`: selections learned locally by PrivatePinyin.

Clearing one writable layer does not clear the other. Importing or clearing a Rime dictionary takes effect after the engine/session is recreated; platform controls perform or request that reload.

## Accepted Input

- Local `.yaml`, `.yml`, or `.dict` text files.
- Rime YAML headers are allowed.
- Dictionary rows must contain `phrase<TAB>pinyin` and may contain a numeric weight.
- Han phrases and normalized pinyin are required.
- Tone marks/numbers and `v`/`u:` spellings are normalized.
- Rows that rely on automatic pronunciation from another Rime schema are skipped.

Each source file is capped at 16 MiB, the canonical imported file at 32 MiB, individual lines at 4 KiB, phrases at 32 Han characters, and the merged imported layer at 200,000 entries. The importer never follows a URL, invokes Rime code, or loads schema plugins.

## Licensing

PrivatePinyin does not bundle or redistribute rime-ice. Its upstream GPL license is not used for the default asset. A user who imports rime-ice or another Rime dictionary supplies that local copy and remains responsible for its license terms.

The default supplemental phrase data comes from `mozillazg/phrase-pinyin-data` v0.19.0 under MIT; its exact revision and notice are recorded in `ime_core/assets/lexicon_manifest.json` and `THIRD_PARTY_NOTICES.md`.

## Platform Entry Points

- macOS: 猫栈拼音 menu or Station Board preferences, `导入 Rime 词库...`.
- Windows: 偏好设置 > 隐私与词库 > 本地导入词库.
- iOS: container App > `本地导入词库` opens the system document picker. While the selected security-scoped files are available, the container App calls the same Rust importer and writes the bounded `imported_lexicon.tsv` layer into the App Group. The keyboard extension only reads that layer, so it does not need Full Access, arbitrary document access, or a second parser. If App Group storage is unavailable, importing is disabled and normal typing continues with the bundled base.

CLI example:

```bash
cargo run -p private_pinyin_settings -- \
  import-rime-lexicon \
  --settings /path/to/settings.json \
  --input /path/to/user.dict.yaml
```
