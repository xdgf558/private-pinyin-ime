# iOS TestFlight Upload Record

Stage 16 uses this record to separate repository-side archive/upload readiness
from owner-side App Store Connect evidence.

## Environment

| Field | Value |
|---|---|
| Tester | Owner/Codex signed archive run |
| Date | 2026-07-17 07:48 +08 |
| Commit | Release metadata based on merged `main` commit `4e9f032` |
| Archive | `dist/ios/PrivatePinyin-0.1.20-build16-xcode26.xcarchive` |
| Export path | Direct App Store Connect upload through `xcodebuild -exportArchive` |
| Package summary | Xcode distribution logs, altool upload/status output, and App Store Connect TestFlight build table |
| App bundle ID | `com.privatepinyin.ios` |
| Keyboard bundle ID | `com.privatepinyin.ios.keyboard` |
| App Group ID | `group.com.privatepinyin.ios` |
| Export destination | `upload` |
| Current candidate | `0.1.20 (16)` Station Cat keyboard UI and navigation TestFlight upload |

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
| Archive | `xcodebuild archive` produces the signed release archive | passed | `dist/ios/PrivatePinyin-0.1.20-build16-xcode26.xcarchive`; Xcode 26.6 (`17F109`) / iPhoneOS 26.5; archive metadata reports `0.1.20 (16)` and arm64; the bundled SQLite object was rebuilt and verified with `minos 18.0` / SDK 26.5 |
| Export or upload | `xcodebuild -exportArchive` completes with ExportOptions `destination=upload` | passed | Xcode reported `Upload succeeded`; delivery UUID `9824d39f-ef1a-4fe2-a024-ad0bfd86b0be` |
| Package summary | `dist/ios/package_summary.txt` records mode, bundle IDs, App Group, and paths | superseded | Manual automatic-signing run recorded here because the scripted manual-profile path was not used |

## App Store Connect

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Uploaded build | Build appears in App Store Connect | uploaded | App Store Connect app ID `6789098978`; version `0.1.20`; build `16`; external-capable upload delivery `9824d39f-ef1a-4fe2-a024-ad0bfd86b0be` |
| Processing | Build processing completes | passed | Apple returned `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, and `IS-ON-APP-STORE-CONNECT: true` |
| TestFlight availability | Processed build can be assigned to a TestFlight group | passed | Build `16` is available in App Store Connect and was submitted for external Beta App Review |
| External testing metadata | Beta description, privacy URL, feedback channel, review contact, and review notes are configured | passed | Filled in App Store Connect TestFlight test information; personal contact details stay out of the repository |
| External testing build | Existing external group and review state are recorded separately from upload readiness | waiting for review | Apple returned `BUILD-STATUS: WAITING_FOR_REVIEW` and `BETA-REVIEW-STATE: WAITING_FOR_REVIEW`; submitted at 2026-07-17 07:53 +08 |

## Stage 17 External Testing Follow-up

- Build `0.1.10 (10)` cannot be reused for external TestFlight because it is
  already marked internal-only in App Store Connect.
- The external-capable upload template intentionally omits
  `testFlightInternalTestingOnly`.
- Container app and keyboard extension `CFBundleVersion` are bumped to `11` for
  the next upload while keeping `CFBundleShortVersionString` at `0.1.10`.
- Build `0.1.10 (11)` was added to the external testing group and submitted for
  external Beta App Review; its public link is not live while review is pending.
- Build `0.1.12 (13)` contains the localized onboarding, continuous-pinyin core,
  keyboard rendering optimization, weighted layout, and inline preferences.
- Build `13` uploaded and processed successfully as App Store eligible. Assigning
  it to the external group is intentionally left separate from this upload so the
  existing build `11` review state is not changed implicitly.
- Build `0.1.18 (14)` adds bounded local trigram learning, 30-day inactivity
  decay, and capacity-based eviction through the shared Rust core.
- An initial build 14 archive made with Xcode 27.0 beta (`27A5194q`) was rejected
  before import because that beta SDK was no longer accepted by App Store Connect.
  Rebuilding with Xcode 26.6 (`17F109`) succeeded and produced delivery
  `2bcd0055-5594-46bd-aa56-d8193b53ba58` with `VALID` and
  `APP_STORE_ELIGIBLE` status.
- Build `0.1.20 (16)` contains the approved Station Cat keyboard redesign,
  touch-down character response, five-candidate paging controls, persistent
  full-key/nine-key selection, and shared OI-045 mixed-pinyin decoding.
- Build `16` was archived with Xcode 26.6 after rebuilding the Rust SQLite
  object for iOS 18 (`minos 18.0`, SDK 26.5). Xcode uploaded delivery
  `9824d39f-ef1a-4fe2-a024-ad0bfd86b0be`; Apple validated it as App Store
  eligible and accepted it for external Beta App Review.

Manual failures should update `docs/OPEN_ITEMS.md` before Stage 17 begins.
