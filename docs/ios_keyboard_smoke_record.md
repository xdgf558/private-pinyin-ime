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

## Station Cat UI And Navigation Regression (2026-07-16)

| Field | Value |
|---|---|
| Tester | Codex iOS 27 Simulator smoke |
| Simulator | iPhone 17 Pro, iOS 27.0 |
| Xcode | 27.0 (`27A5194q`) |
| Branch | `codex/fix-ios-nine-key-navigation` |
| Build artifact | `/private/tmp/private_pinyin_ios_ui_signed/Build/Products/Debug-iphonesimulator/PrivatePinyin.app` |

| Check | Result | Evidence / notes |
|---|---|---|
| Station Cat visual handoff | passed | Warm dark tray, orange accent, compact 46-point candidate strip, key gradients, inline preferences, and pressed states rendered without clipping |
| QWERTY geometry | passed | Ten-key first row, inset nine-key second row, Shift + seven letters + Delete third row, and adaptive bottom command row fit the iPhone 17 Pro portrait viewport |
| Immediate key response | passed | Letter keys use touch-down delivery; one `n` tap plus one `h` tap produced exactly `nh` and ranked `你好` first |
| Candidate groups | passed | `a` displayed a fixed next-page chevron; page two displayed a fixed previous-page chevron; both controls remained reachable outside the horizontal scroller |
| Nine-key geometry | passed | Four-column layout placed punctuation/ABC/DEF/Delete, 123/GHI/JKL/MNO, and `全键`/PQRS/TUV/WXYZ as specified, with Space spanning the center of the final row |
| Nine-key composition | passed | Tapping `64426` ranked `你好` first; one candidate tap inserted exactly one `你好` in Messages |
| Layout persistence | passed | Selecting `九宫` in inline preferences rebuilt the keyboard and the stored setting remained active after the preferences panel closed |
| System controls | passed | iOS continued to provide the bottom Globe/dictation row; the extension did not duplicate a non-functional microphone button |

Password-field, phone-field, distribution App Group, and final real-device latency
checks remain part of Stage 17 and are not replaced by this Simulator record.

## iOS Keyboard Regression Readiness (2026-07-18)

| Field | Value |
|---|---|
| Tester | Codex automated tests and headless iOS 27 Simulator readiness |
| Simulator | iPhone 17 Pro, iOS 27.0 |
| Xcode | 27.0 (`27A5194q`) |
| Branch | `codex/fix-ios-keyboard-regressions` |
| Build artifact | `build/ios_keyboard/Build/Products/Debug-iphonesimulator/PrivatePinyin.app` |

| Check | Result | Evidence / notes |
|---|---|---|
| Rust workspace | passed | `cargo test --workspace`, formatting, and Clippy with warnings denied passed |
| iOS source gate | passed | `scripts/check_ios_keyboard_sources.sh` validates extension-local settings fallback, delayed self-change handling, symbol entry, and the revised grid contract |
| Xcode build | passed | Xcode 27 Simulator build reported `BUILD SUCCEEDED` |
| Simulator install/launch | passed | Installed and launched `com.privatepinyin.ios` on the iOS 27.0 simulator |
| Layout/script persistence | passed (headless) | Wrote `nine_key` and `traditional` to the extension-local preference domain, fully restarted the simulator, and read both values back unchanged |
| Nine-key core input | passed | Four focused tests cover `64426 -> 你好`, continuous digit segmentation, Backspace/commit behavior, and the interactive lookup budget |
| Mixed shorthand | passed | `zyao` ranks `主要 (zhu yao)` first and the new regression passes with the production lexicon |
| Host UI taps | pending device/manual pass | Recheck candidate taps, top-left symbol selection, revised nine-key geometry, and delayed callback behavior in the TestFlight/device build before release |

The headless persistence pass verifies the regression that previously returned
to QWERTY after switching apps. It does not replace the final host-app tap and
layout pass on a real device.
