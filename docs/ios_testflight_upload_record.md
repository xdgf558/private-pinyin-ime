# iOS TestFlight Upload Record

Stage 16 uses this record to separate repository-side archive/upload readiness
from owner-side App Store Connect evidence.

## Environment

| Field | Value |
|---|---|
| Tester | Owner/Codex signed archive run |
| Date | 2026-07-09 18:58 +08 |
| Commit | `685ab73` plus local Stage 17/TestFlight follow-up changes |
| Archive | `dist/ios/PrivatePinyin-stage17-xcode26.xcarchive` |
| Export path | `dist/ios/export-automatic-stage17-fix` |
| Package summary | Xcode distribution logs and App Store Connect TestFlight build table |
| App bundle ID | `com.privatepinyin.ios` |
| Keyboard bundle ID | `com.privatepinyin.ios.keyboard` |
| App Group ID | `group.com.privatepinyin.ios` |
| Export destination | `upload` |

## Archive And Export

Run:

```bash
. platform/ios_keyboard/AppStoreMetadata/Signing.env
bash scripts/package_ios_app_store.sh
```

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Owner signing env | Team ID, app bundle ID, keyboard bundle ID, App Group ID, ExportOptions plist, and profiles are configured | passed | Team `Y35K7AQ974`; App Group `group.com.privatepinyin.ios`; automatic signing created App Store profiles |
| App Store Connect API key | Upload mode has key path, key ID, and issuer ID configured | not used | Upload used the signed-in Xcode account and Cloud Managed Apple Distribution certificate |
| Archive | `xcodebuild archive` produces `dist/ios/PrivatePinyin.xcarchive` | passed | `dist/ios/PrivatePinyin-stage17-xcode26.xcarchive`; Xcode 26.6 / iPhoneOS 26.5 |
| Export or upload | `xcodebuild -exportArchive` completes with ExportOptions `destination` | passed | Xcode output: `Uploaded package is processing`; `Upload succeeded`; `Uploaded PrivatePinyin` |
| Package summary | `dist/ios/package_summary.txt` records mode, bundle IDs, App Group, and paths | superseded | Manual automatic-signing run recorded here because the scripted manual-profile path was not used |

## App Store Connect

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Uploaded build | Build appears in App Store Connect | passed | App Store Connect app ID `6789098978`; version `0.1.10`; build `10`; internal build |
| Processing | Build processing completes | passed | Status changed from `缺少出口合规证明` to `准备测试` after export-compliance declaration |
| TestFlight availability | Build can be distributed to internal testers | ready | Build is ready for testing; internal tester group/invite still needs Owner action before device install |
| External testing | Product decision recorded if external TestFlight is enabled | pending | |

Manual failures should update `docs/OPEN_ITEMS.md` before Stage 17 begins.
