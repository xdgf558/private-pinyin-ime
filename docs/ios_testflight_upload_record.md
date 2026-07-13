# iOS TestFlight Upload Record

Stage 16 uses this record to separate repository-side archive/upload readiness
from owner-side App Store Connect evidence.

## Environment

| Field | Value |
|---|---|
| Tester | Owner/Codex signed archive run |
| Date | 2026-07-13 14:41 +08 |
| Commit | Local build 14 candidate based on `main` |
| Archive | `dist/ios/PrivatePinyin-build14-xcode26.xcarchive` |
| Export path | Direct App Store Connect upload through `xcodebuild -exportArchive` |
| Package summary | Xcode distribution logs, altool upload/status output, and App Store Connect TestFlight build table |
| App bundle ID | `com.privatepinyin.ios` |
| Keyboard bundle ID | `com.privatepinyin.ios.keyboard` |
| App Group ID | `group.com.privatepinyin.ios` |
| Export destination | `upload` |
| Current candidate | `0.1.18 (14)` local trigram TestFlight upload |

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
| Archive | `xcodebuild archive` produces the signed release archive | passed | `dist/ios/PrivatePinyin-build14-xcode26.xcarchive`; Xcode 26.6 (`17F109`) / iPhoneOS 26.5; archive metadata reports `0.1.18 (14)` and arm64 |
| Export or upload | `xcodebuild -exportArchive` completes with ExportOptions `destination=upload` | passed | Xcode reported `Upload succeeded`; delivery UUID `2bcd0055-5594-46bd-aa56-d8193b53ba58` |
| Package summary | `dist/ios/package_summary.txt` records mode, bundle IDs, App Group, and paths | superseded | Manual automatic-signing run recorded here because the scripted manual-profile path was not used |

## App Store Connect

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Uploaded build | Build appears in App Store Connect | passed | App Store Connect app ID `6789098978`; version `0.1.18`; build `14`; external-capable upload |
| Processing | Build processing completes | passed | altool reported `import-status=VALID`, `build-audience-type=APP_STORE_ELIGIBLE`, and `is-on-app-store-connect=true` |
| TestFlight availability | Processed build can be assigned to a TestFlight group | ready | Build `14` processed as `BETA_INTERNAL_TESTING`; it has not yet been assigned to the external group |
| External testing metadata | Beta description, privacy URL, feedback channel, review contact, and review notes are configured | passed | Filled in App Store Connect TestFlight test information; personal contact details stay out of the repository |
| External testing build | Existing external group and review state are recorded separately from upload readiness | pending assignment | Build `14` remains unassigned after upload; changing the external group is intentionally separate from archive readiness |

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

Manual failures should update `docs/OPEN_ITEMS.md` before Stage 17 begins.
