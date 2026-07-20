# Local Rime Lexicon Import

PrivatePinyin ships a reviewed permissive base dictionary for every user. Advanced users can additionally import local Rime YAML dictionaries without replacing that base.

## Storage Model

The three layers are independent:

1. `base_lexicon.tsv`: immutable, bundled, reviewed Apache-2.0/MIT data.
2. `imported_lexicon.tsv`: user-selected Rime rows; preserved by app upgrades.
3. `imported_lexicon_manifest.json`: source names/versions for UI only; no rows or source paths.
4. `user_lexicon.sqlite`: selections learned locally by PrivatePinyin.

Clearing one writable layer does not clear the other. Importing or clearing a Rime dictionary takes effect after the engine/session is recreated; platform controls perform or request that reload.

Source labels are captured only when an import succeeds. On macOS, files selected from a path containing `rime-ice`, `雾凇`, or `霧凇` are shown as `雾凇拼音`; other dictionaries use a cleaned filename. Legacy imported layers created before the source manifest existed cannot reconstruct their origin from normalized phrase/pinyin rows, so the preferences UI asks the user to re-import the original files. Re-importing is cumulative and deduplicated, and records the source label without duplicating phrase/pinyin identities.

## Accepted Input

- Local `.yaml`, `.yml`, or `.dict` text files.
- Rime YAML headers are allowed.
- Dictionary rows must contain `phrase<TAB>pinyin` and may contain a numeric weight.
- Han phrases and normalized pinyin are required.
- Tone marks/numbers and `v`/`u:` spellings are normalized.
- Rows that rely on automatic pronunciation from another Rime schema are skipped.

Each source file is capped at 16 MiB, the canonical imported file at 32 MiB, individual lines at 4 KiB, phrases at 32 Han characters, and the merged imported layer at 200,000 entries. The shared Rust importer never follows a URL, invokes Rime code, or loads schema plugins.

The 4 KiB line limit is checked before comments are discarded. A line containing only `---` starts a YAML header and a line containing only `...` ends it; those delimiter-only lines are therefore reserved and must not appear in dictionary data. An unclosed header causes the remaining rows to be ignored and the import fails when no usable rows remain.

## Merge, Failure, and Recovery

Imports are cumulative. Re-importing a phrase/pinyin identity keeps the highest supplied weight, and a successful single-file import replaces the canonical layer atomically. If the merged result would exceed a size or entry limit, the existing canonical file remains unchanged.

Multi-file selection is currently processed one file at a time. If a later file fails, earlier files remain imported and the host reports the accepted row count; the selection is not an all-or-nothing transaction. Do not start imports concurrently from multiple processes because the last atomic replacement can supersede another process's newly imported rows.

If `imported_lexicon.tsv` is damaged, normal engine creation ignores that layer and preserves base typing, but a later merge is refused to avoid silently deleting local data. Use `Clear Imported Lexicon` and import the source dictionaries again. The importer never deletes a damaged layer automatically.

## Licensing

PrivatePinyin does not bundle or redistribute `rime-ice`. Its GPL-3.0-only data is not used for the default asset. Local file imports remain the user's choice. The iOS container App additionally offers an explicit opt-in import of a reviewed upstream subset and shows the source/license before downloading; those optional data remain a separate GPL layer and are never copied into the app package.

The reviewed iOS action is pinned to official release `2026.03.26` and imports only:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `cn_dicts/8105.dict.yaml` | 114070 | `5968cddbf08f9aab7f56a37f265f7d7af85d5222079e5eebdf1bae94b0cdf67d` |
| `cn_dicts/41448.dict.yaml` | 387281 | `873df74783f565e01581938b14bdf41b4e03a8834791f8778ebcbd70054a26d0` |
| `cn_dicts/others.dict.yaml` | 16862 | `6a6b1a77d94c7cdf9203cf426e67f350215d2d73259fe3769c97d2a18f521c28` |

### Hash provenance (2026-07-20)

The values above were independently captured from the official `iDvel/rime-ice` GitHub release `2026.03.26`, published at `2026-03-26T10:48:41Z`. The official `cn_dicts.zip` release asset was 14,711,733 bytes and reported the GitHub digest `sha256:4539b66898fa585a75a8680bf72854ccc09beeeed78f61c3b35123c04f7e91f1`.

The review downloaded that asset with `gh release download`, extracted it with `/usr/bin/unzip`, and calculated each selected file with `/usr/bin/shasum -a 256`. A second capture downloaded the three fixed raw tag URLs with `/usr/bin/curl --fail --location`; their byte counts and SHA-256 values exactly matched the files extracted from the official release asset. CI intentionally makes no network request and instead pins these reviewed values. Any upstream tag movement or asset replacement therefore fails closed until the Owner reviews and records a new release.

This is deliberately labeled `雾凇拼音精选`, not a complete upstream installation. The larger `base`, `ext`, and `tencent` dictionaries do not fit the current per-source or 200,000-entry import policy and are not downloaded.

The default supplemental phrase data comes from `mozillazg/phrase-pinyin-data` v0.19.0 under MIT; its exact revision and notice are recorded in `ime_core/assets/lexicon_manifest.json` and `THIRD_PARTY_NOTICES.md`.

## Platform Entry Points

- macOS: 猫栈拼音 menu or Station Board preferences, `导入 Rime 词库...`.
- Windows: 偏好设置 > 隐私与词库 > 本地导入词库.
- iOS: container App > `本地导入词库` opens the system document picker. `一键导入雾凇精选` is a separate default-off action that requires confirmation, downloads only the pinned files above through an ephemeral session, and rejects any host, size, or SHA-256 mismatch. In both paths the container App calls the same Rust importer and writes the bounded `imported_lexicon.tsv` layer into the App Group. The keyboard extension only reads that layer, so it does not need Full Access, arbitrary document access, a network API, or a second parser. If App Group storage is unavailable, importing is disabled and normal typing continues with the bundled base.

CLI example:

```bash
cargo run -p private_pinyin_settings -- \
  import-rime-lexicon \
  --settings /path/to/settings.json \
  --input /path/to/user.dict.yaml
```
