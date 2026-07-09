# iOS TestFlight Upload Record

Stage 16 uses this record to separate repository-side archive/upload readiness
from owner-side App Store Connect evidence.

## Environment

| Field | Value |
|---|---|
| Tester | pending Owner/Codex signed archive run |
| Date | pending |
| Commit | pending Stage 16 commit |
| Archive | `dist/ios/PrivatePinyin.xcarchive` |
| Export path | `dist/ios/export` |
| Package summary | `dist/ios/package_summary.txt` |
| App bundle ID | pending owner value |
| Keyboard bundle ID | pending owner value |
| App Group ID | pending owner value |
| Export destination | `export` or `upload` |

## Archive And Export

Run:

```bash
. platform/ios_keyboard/AppStoreMetadata/Signing.env
bash scripts/package_ios_app_store.sh
```

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Owner signing env | Team ID, app bundle ID, keyboard bundle ID, App Group ID, ExportOptions plist, and profiles are configured | pending | |
| App Store Connect API key | Upload mode has key path, key ID, and issuer ID configured | pending | Required only when `destination=upload` |
| Archive | `xcodebuild archive` produces `dist/ios/PrivatePinyin.xcarchive` | pending | |
| Export or upload | `xcodebuild -exportArchive` completes with ExportOptions `destination` | pending | |
| Package summary | `dist/ios/package_summary.txt` records mode, bundle IDs, App Group, and paths | pending | |

## App Store Connect

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Uploaded build | Build appears in App Store Connect | pending | Build number: pending |
| Processing | Build processing completes | pending | |
| TestFlight availability | Build can be distributed to internal testers | pending | |
| External testing | Product decision recorded if external TestFlight is enabled | pending | |

Manual failures should update `docs/OPEN_ITEMS.md` before Stage 17 begins.
