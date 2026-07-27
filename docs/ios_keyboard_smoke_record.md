# iOS Keyboard Smoke Record

Stage 15 records the automated readiness checks that can run from the repository
and separates the remaining iOS keyboard behavior that must be verified in
Simulator or on a device.

## Host Submission Transition Smoothing (2026-07-27)

| Field | Value |
|---|---|
| Tester | Codex interactive simulator smoke |
| Simulator | iPhone 17 Pro, iOS 26.5 |
| Xcode | 26.6 (`17F109`) |
| Branch | `codex/ios-dismissal-transition-smoothing` |
| Build artifact | `build/ios_keyboard/Build/Products/Debug-iphonesimulator/PrivatePinyin.app` |

| Check | Result | Evidence / notes |
|---|---|---|
| Source contract | passed | `scripts/check_ios_keyboard_sources.sh` verified the document-change, disappearance-freeze, redundant thaw, active-key recovery, explicit layout recovery, and coalesced-refresh lifecycle hooks |
| Simulator build | passed | The container App and Keyboard Extension completed with `BUILD SUCCEEDED` |
| Nine-key input | passed | The real custom surface entered `64426`, displayed `ni hao`, ranked `你好` first, and one candidate tap inserted exactly one `你好` |
| Host dismissal | passed (equivalent host transition) | With the custom keyboard visible, navigating from the focused diagnostic field to the About page dismissed the extension and completed the host transition without a second visible pull |
| Warm reuse thaw | passed | Returned from the About page to the same diagnostic field without recreating the App, entered `64426` again, observed the live `ni hao` / `你好` candidate strip, and committed exactly once; the field changed from `你好` to `你好你好` |
| Layout/crash scan | passed | The dismissal log contained no Auto Layout conflict, and no new PrivatePinyin crash report was produced |
| X Publish | pending physical device | X's exact post-publication animation is not available in Simulator; repeat the same check in the next TestFlight build |

This pass validates the lifecycle fix and its host-animation boundary. It does
not replace the physical-device X Publish check.

## Physical X Submission Follow-up (2026-07-27)

| Check | Result | Evidence / notes |
|---|---|---|
| Physical-device report | reproduced | TestFlight `0.1.28 (24)` still showed about one second of host-view pulling after tapping Publish in X; the supplied capture shows the keyboard dismissed while X remains in its `正在发送帖子...` transition |
| Earlier freeze boundary | insufficient | `viewWillDisappear` can arrive after X's external document-change callbacks, leaving a gap where a fast queued reset may still request height and root-stack layout |
| Revised source contract | passed | External `textWillChange` now freezes the visible surface immediately; key-event recovery is presentation-gated, compact paging arrows are removed, and feedback generators are attached to the keyboard view. `scripts/check_ios_keyboard_sources.sh` passed |
| Xcode 26.6 simulator build | passed | Clean arm64 iOS 26.5 simulator build produced `PrivatePinyin.app` and `PrivatePinyinKeyboard.appex` with the view-attached feedback APIs |
| Simulator candidate and warm-reuse smoke | passed | Typed `hai`: the compact strip showed only the downward expansion entry, the expanded 3-by-3 grid retained later-page navigation, and dismissing/reopening the warm keyboard allowed a fresh `ni` composition and candidates |
| Physical-device retest | pending | Repeat X Publish/Send with `0.1.29` or the next TestFlight candidate, then return to the same input field and verify live candidates plus physical haptic feedback |

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
| AI Lite hardware matrix | pending device/manual pass | Use at least one 8-GiB iPhone to exercise enabled AI and one sub-8-GiB iPhone to confirm unchanged base-order fallback; capture first-enable latency, extension RSS, and memory-warning behavior without recording input content |

The headless persistence pass verifies the regression that previously returned
to QWERTY after switching apps. It does not replace the final host-app tap and
layout pass on a real device.

## iOS Keyboard Responsiveness Regression (2026-07-24)

| Field | Value |
|---|---|
| Tester | Codex interactive iOS 27 Simulator smoke |
| Simulator | iPhone 17 Pro, iOS 27.0 |
| Xcode | 26.6 (`17F109`) |
| Branch | `codex/ios-keyboard-responsiveness` |
| Build artifact | `build/ios_keyboard/Build/Products/Debug-iphonesimulator/PrivatePinyin.app` |

| Check | Result | Evidence / notes |
|---|---|---|
| Automated readiness | passed | `scripts/run_ios_smoke_readiness.sh` completed source checks and reported `BUILD SUCCEEDED` with the Beta Xcode toolchain |
| Install and enable | passed | Installed `com.privatepinyin.ios`; the simulator's enabled keyboard list included `com.privatepinyin.ios.keyboard` |
| Nine-key rapid input | passed | Five `64426` key taps completed in about 346 ms including UI automation overhead; the strip displayed readable `ni hao`, ranked `你好` first, and one candidate tap inserted exactly one `你好` |
| QWERTY rapid input | passed | Five `nihao` key taps completed in about 203 ms including UI automation overhead; the strip displayed `nihao`, ranked `你好` first, and one candidate tap inserted exactly one additional `你好` |
| Raw nine-key digits | passed | The visible preedit used candidate pinyin instead of exposing the internal `64426` lookup signature |
| Keyboard transitions | passed | Six consecutive Globe-key transitions returned to a complete custom QWERTY surface; the host field retained `你好你好` and no blank or partially built keyboard was observed |
| Crash scan | passed | No new PrivatePinyin crash report appeared in the simulator data after typing, candidate commits, and repeated keyboard transitions |
| Haptic feedback | pending physical device | Typing and selection feedback generators are wired and source-gated, but Simulator cannot validate whether iOS emits or suppresses the physical feedback |
| Host-App compatibility boundary | pending physical device | Notes/Safari, password/phone fallback, and an App that rejects third-party keyboards must be recorded separately; the extension cannot override a host rejection |

This pass validates the off-main serialized core path and visible regression
behavior. It is not a substitute for the Stage 17 TestFlight device matrix.
