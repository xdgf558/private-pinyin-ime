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

The 4 KiB line limit is checked before comments are discarded. A line containing only `---` starts a YAML header and a line containing only `...` ends it; those delimiter-only lines are therefore reserved and must not appear in dictionary data. An unclosed header causes the remaining rows to be ignored and the import fails when no usable rows remain.

## Merge, Failure, and Recovery

Imports are cumulative. Re-importing a phrase/pinyin identity keeps the highest supplied weight, and a successful single-file import replaces the canonical layer atomically. If the merged result would exceed a size or entry limit, the existing canonical file remains unchanged.

Multi-file selection is currently processed one file at a time. If a later file fails, earlier files remain imported and the host reports the accepted row count; the selection is not an all-or-nothing transaction. Do not start imports concurrently from multiple processes because the last atomic replacement can supersede another process's newly imported rows.

If `imported_lexicon.tsv` is damaged, normal engine creation ignores that layer and preserves base typing, but a later merge is refused to avoid silently deleting local data. Use `Clear Imported Lexicon` and import the source dictionaries again. The importer never deletes a damaged layer automatically.

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
