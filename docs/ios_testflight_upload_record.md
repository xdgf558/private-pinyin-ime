# iOS TestFlight Upload Record

Stage 16 uses this record to separate repository-side archive/upload readiness
from owner-side App Store Connect evidence.

## Environment

| Field | Value |
|---|---|
| Tester | Owner/Codex signed archive run |
| Date | 2026-07-26 19:37 +08 |
| Commit | Release changes based on merged `main` commit `e12f6f7` |
| Archive | `dist/ios/PrivatePinyin-0.1.27-build23-xcode26.xcarchive` |
| Export path | Direct App Store Connect upload through `xcodebuild -exportArchive` |
| Package summary | Xcode distribution logs, altool upload/status output, and App Store Connect TestFlight build table |
| App bundle ID | `com.privatepinyin.ios` |
| Keyboard bundle ID | `com.privatepinyin.ios.keyboard` |
| App Group ID | `group.com.privatepinyin.ios` |
| Export destination | `upload` |
| Current candidate | `0.1.27 (23)` NINEKEY-PERF-01 exact-key lookup, complete candidate equivalence coverage, and bounded incremental nine-key lattice reuse |

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
| Archive | `xcodebuild archive` produces the signed release archive | passed | `dist/ios/PrivatePinyin-0.1.27-build23-xcode26.xcarchive`; Xcode 26.6 (`17F109`) / iPhoneOS 26.5; archive, container App, and Keyboard Extension metadata all report `0.1.27 (23)`, arm64, and iOS 18 minimum |
| Export or upload | `xcodebuild -exportArchive` completes with ExportOptions `destination=upload` | passed | Xcode reported `Upload succeeded`; delivery UUID `f1fd7ee0-9b84-4963-9f8d-d8f166fe780a`; the 6,608,723-byte IPA reached `COMPLETE` with no upload errors or warnings; `manageAppVersionAndBuildNumber=false` preserved build `23` |
| Package summary | `dist/ios/package_summary.txt` records mode, bundle IDs, App Group, and paths | superseded | Manual automatic-signing run recorded here because the scripted manual-profile path was not used |

## App Store Connect

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Uploaded build | Build appears in App Store Connect | uploaded | App Store Connect app ID `6789098978`; version `0.1.27`; build `23`; delivery `f1fd7ee0-9b84-4963-9f8d-d8f166fe780a` |
| Processing | Build processing completes | pending | Upload transport completed without errors; App Store Connect is processing `0.1.27 (23)` |
| TestFlight availability | Processed build can be assigned to a TestFlight group | pending | Assign build `23` after App Store Connect finishes processing |
| External testing metadata | Beta description, privacy URL, feedback channel, review contact, and review notes are configured | passed | Filled in App Store Connect TestFlight test information; personal contact details stay out of the repository |
| External testing build | Existing external group and review state are recorded separately from upload readiness | pending owner submission | After processing, assigning build `23` to the external group and submitting Beta App Review remain explicit App Store Connect actions |

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
- Build `0.1.21 (17)` adds readable nine-key composition, generic Return
  behavior, persistent local Simplified/Traditional output, nine-candidate
  paging, and the expanded symbol surface approved in PR #31.
- Build `17` was archived with Xcode 26.6 and uploaded as delivery
  `cd60fb42-9506-4aee-a7e8-4d71bb9d55cb`. Apple returned `VALID`,
  `APP_STORE_ELIGIBLE`, `BETA_INTERNAL_TESTING`, and
  `IS-ON-APP-STORE-CONNECT: true`; external group submission remains a
  separate Owner action.
- Build `0.1.22 (18)` contains the approved PR #32 fixes for persistent
  layout/script preferences, candidate retention after delayed host callbacks,
  revised nine-key symbols and key placement, and bounded mixed shorthand
  decoding such as `zyao -> 主要`.
- Build `18` was archived with Xcode 26.6 and uploaded as delivery
  `fe40dc42-10f0-4c4c-abd5-5bd9da81e122`. Apple returned `VALID`,
  `APP_STORE_ELIGIBLE`, `BETA_INTERNAL_TESTING`, and
  `IS-ON-APP-STORE-CONNECT: true`; external group submission remains a
  separate Owner action.
- Build `0.1.24 (20)` repairs Keyboard Extension activation, adds the expandable
  nine-candidate browser, reduces lexicon-index memory, and includes the explicit
  verified `rime-ice` import action alongside local document import.
- Build `20` was archived with Xcode 26.6 and uploaded as delivery
  `e25c8f4b-64b2-46a6-b4d3-e83dbf8810d3`. Apple returned `VALID`,
  `APP_STORE_ELIGIBLE`, `BETA_INTERNAL_TESTING`, and
  `IS-ON-APP-STORE-CONNECT: true`; external group submission remains a
  separate Owner action.
- Build `0.1.25 (21)` adds smoother cold keyboard activation, dedicated
  nine-key numeric and punctuation surfaces, the two-level container settings
  interface, and the merged AI-12 release hardening gates.
- Build `21` was archived with Xcode 26.6 and uploaded as delivery
  `7388b499-48c5-470e-89f4-95569a6b7309`. Apple returned `VALID`,
  `APP_STORE_ELIGIBLE`, `BETA_INTERNAL_TESTING`, and
  `IS-ON-APP-STORE-CONNECT: true`; external group submission remains a
  separate Owner action.
- The superseded build `0.1.26 (23)` adds the approved NINEKEY-PERF-01 exact-key lookup,
  complete stateless/incremental candidate equivalence regressions, and a
  bounded nine-key lattice cache that retains the Apple 60-ms per-key budget.
- Xcode 26.6 archived source build `22` and, because managed App Store numbering
  was still using its default, uploaded build `23`. Delivery
  `840e9dc7-8e12-4286-a9da-c147abe2ebab` completed without upload errors or
  warnings. Source metadata is aligned to `23`, and future exports explicitly
  preserve repository build numbers.
- Because `0.1.26 (22)` was already waiting for external Beta App Review,
  App Store Connect would not accept another `0.1.26` build into the review
  flow. The active candidate therefore advances to `0.1.27 (23)`; the
  superseded `0.1.26 (23)` delivery remains unassigned.
- Xcode 26.6 uploaded the corrected `0.1.27 (23)` candidate as delivery
  `f1fd7ee0-9b84-4963-9f8d-d8f166fe780a`. The 6,608,723-byte IPA completed
  transport with an empty Apple error and warning set and entered App Store
  Connect processing.

Manual failures should update `docs/OPEN_ITEMS.md` before Stage 17 begins.
