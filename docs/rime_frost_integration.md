# Reviewed White Frost Desktop Import

FROST-01 adds an optional White Frost dictionary layer to macOS and Windows. It does not add White Frost data to the repository, application bundle, installer, permissive base lexicon, or iOS Keyboard Extension.

## Reviewed Source

| Field | Approved value |
| --- | --- |
| Project | `gaboolic/rime-frost` |
| Repository | `https://github.com/gaboolic/rime-frost` |
| License | GPL-3.0 |
| Stable release | `1.0.4` |
| Published | 2026-05-08 |
| Release commit | `89ad92e` |
| Asset | `rime-frost-schemas.zip` |
| Asset URL | `https://github.com/gaboolic/rime-frost/releases/download/1.0.4/rime-frost-schemas.zip` |
| Exact bytes | `44,008,360` |
| SHA-256 | `4f4998ae83f63d757c0a4ace192f69d48265bddfabe231642b73e3739ed0f2f5` |
| Archive entries | `161` |
| Expanded bytes | `109,297,719` |

### Artifact Capture

The artifact identity was captured on 2026-07-24 from the official GitHub Release page and asset URL. The asset was downloaded with redirect following from the fixed `github.com/gaboolic/rime-frost` URL. Its byte count was read from the downloaded file and its digest was calculated with SHA-256. The archive inventory was inspected without running upstream code.

The application and CI never trust a moving branch. Both desktop hosts pin the URL, version, exact byte count, and SHA-256 above. A release check may report a different official tag, but the UI labels it `新版待审核` and cannot import it until the Owner repeats this review and updates all pinned values.

## License Boundary

White Frost is GPL-3.0 data. PrivatePinyin is not redistributing it:

- The app and installers contain no White Frost archive or normalized rows.
- The download starts only after the user sees the source/license and explicitly agrees.
- The downloaded archive is normalized locally into the user's application-data directory.
- White Frost can be disabled or removed without changing any other lexicon layer.
- The optional network request contains no typed content, candidates, context, learning data, account identity, or telemetry.

## Selected Dictionaries

The reviewed importer reads only these members:

| Archive member |
| --- |
| `cn_dicts/8105.dict.yaml` |
| `cn_dicts/41448.dict.yaml` |
| `cn_dicts/base.dict.yaml` |
| `cn_dicts/ext.dict.yaml` |
| `cn_dicts/others.dict.yaml` |
| `cn_dicts/corrections.dict.yaml` |

Other archive members are validated for safe ZIP structure but are not imported. A
2026-07-25 import smoke of the exact approved asset accepted 653,308 source rows
and retained 653,136 unique phrase/pinyin identities after normalization and
deduplication. The resulting canonical TSV was 18,083,664 bytes, including its
header.

## Archive Safety

The shared Rust importer verifies the complete artifact before parsing and never extracts archive members to disk. It rejects:

- A byte-count or SHA-256 mismatch.
- More than 256 archive entries.
- Duplicate, absolute, parent-relative, dot-relative, backslash, NUL, symlink, or special-file members.
- A member larger than 32 MiB.
- More than 128 MiB total expanded data.
- A compression ratio above 200:1.
- Missing approved dictionary members.
- Invalid Rime rows or a normalized result above the desktop 750,000-entry/128-MiB policy.

The canonical output is written through `AtomicFile`. Verification, ZIP validation, parsing, limit checking, and deduplication all complete before replacement, so any failure leaves the previous `rime_frost.tsv` untouched.

## Layer Ownership

| Layer | Purpose | Affected by White Frost actions |
| --- | --- | --- |
| Bundled base | Reviewed permissive defaults | No |
| `imported_lexicon.tsv` | Manual local Rime imports | No |
| `rime_ice.tsv` | Reviewed Rime Ice layer | No |
| `rime_frost.tsv` | Reviewed White Frost layer | Yes |
| `user_lexicon.sqlite` | Local learning | No |

macOS and Windows expose import/update, enable/disable, clear, license, and update-check controls. iOS remains unchanged at its existing 16-MiB source, 32-MiB canonical-file, and 200,000-entry limits and has no White Frost action.
