# iOS Keyboard Smoke Record

Stage 15 records the automated readiness checks that can run from the repository
and separates the remaining iOS keyboard behavior that must be verified in
Simulator or on a device.

## Environment

| Field | Value |
|---|---|
| Tester | Codex automated readiness and iOS 27 Simulator smoke |
| Date | 2026-07-10 |
| Commit | `codex/ios-keyboard-performance-settings` build 13 candidate |
| Build artifact | `build/ios_keyboard/Build/Products/Debug-iphonesimulator/PrivatePinyin.app` |
| App bundle ID | `com.privatepinyin.ios` |
| Keyboard bundle ID | `com.privatepinyin.ios.keyboard` |
| App Group ID | `group.com.privatepinyin.ios` |

## Automated Readiness

Run:

```bash
bash scripts/run_ios_smoke_readiness.sh
```

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Source scaffold | Existing iOS and Stage 14 checks pass before build | passed | `scripts/run_ios_smoke_readiness.sh` ran source gates first |
| Build | `scripts/build_ios_keyboard.sh` produces simulator app and keyboard extension | passed | Xcode reported `BUILD SUCCEEDED` |
| Container bundle ID | Built app Info.plist expands to `com.privatepinyin.ios` | passed | Script checked `CFBundleIdentifier` |
| Keyboard bundle ID | Built extension Info.plist expands to `com.privatepinyin.ios.keyboard` | passed | Script checked `CFBundleIdentifier` |
| App Group expansion | Built app and extension expose `group.com.privatepinyin.ios` through `PrivatePinyinAppGroupIdentifier` | passed | Script checked both Info.plist files |
| Full Access request | Keyboard extension keeps `RequestsOpenAccess=false` | passed | Script checked extension Info.plist |
| Primary language | Keyboard extension primary language remains `zh-Hans` | passed | Script checked extension Info.plist |
| Default settings resource | App and extension bundle `default_settings.json` | passed | Script checked both products |
| No network source usage | Keyboard Extension Swift sources contain no network APIs or URLs | passed | Script scanned Keyboard Extension Swift files |

## Manual Smoke Checklist

| Check | Expected result | Result | Evidence / notes |
|---|---|---|---|
| Install | Container app installs on simulator/device | passed (Simulator) | Installed the Beta-Xcode Debug app on an iOS 27.0 iPhone 17 Pro simulator |
| Enable keyboard | Keyboard can be added from Settings > General > Keyboard > Keyboards | passed (Simulator) | Added `猫栈拼音`; Settings showed bundle `com.privatepinyin.ios.keyboard` with language `中文` |
| Full Access | Full Access remains off by default | passed (Simulator) | Keyboard worked with `RequestsOpenAccess=false` and without enabling Full Access |
| Learning opt-in | Keyboard settings show learning disabled by default and allow explicit local opt-in | passed (Simulator) | Opened the gear panel, enabled learning, and verified `enable_user_learning=true` in the extension-local settings file |
| App Group fallback | If App Group access is denied, typing and explicit learning use only the keyboard extension's own sandbox | passed (Simulator) | Unsigned simulator build was denied App Group access; runtime repaired the SQLite path to the current extension container and kept all data local |
| Host composition | Typing `nihao` shows candidate `你好`; tapping it commits `你好` | passed (Safari) | Candidate bar showed `nihao`, first candidate `你好`, and Safari received `你好` |
| Continuous pinyin | Typing a multi-syllable string produces a segmented phrase candidate | passed (Safari) | `wojintian` produced first candidate `我今天` |
| Prediction retention | A committed phrase keeps next-word prediction candidates | passed (Safari) | Committing `你好` kept the prediction `世界` in the candidate bar |
| Keyboard response | Rapid taps update candidates without reconstructing the full keyboard | passed (Simulator) | Five automated `nihao` taps completed in about 250 ms including automation overhead; the key view tree remained stable |
| Layout | Portrait and landscape layouts keep keys legible and non-overlapping | passed (Simulator) | Verified centered second row, wider edit keys, wide space bar, candidate bar, and inline settings in both orientations |
| Inline preferences | Gear panel changes prediction and learning settings without leaving the keyboard | passed (Simulator) | Gear panel opened in place; prediction and local-learning controls rendered and persisted |
| Globe key | Globe appears only when `needsInputModeSwitchKey` requires it and switches input modes | passed (Simulator) | Switched among English, Simplified Pinyin, and `猫栈拼音` |
| Password fallback | Password fields force the system keyboard | pending | |
| Phone fallback | Phone-number fields force the system keyboard | pending | |
| No network prompt | With Full Access off, there is no network prompt | passed (Simulator) | No network permission or network activity was requested during typing and settings changes |

Manual failures should update `docs/OPEN_ITEMS.md` before release-readiness work
continues.
