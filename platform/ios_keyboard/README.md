# iOS Keyboard Extension

This directory contains the iOS container app and custom keyboard extension.

The iOS host remains thin:

- `PrivatePinyin.xcodeproj` builds a SwiftUI container app plus a `UIInputViewController` keyboard extension.
- `PrivatePinyinC/module.modulemap` imports the shared C ABI from `ffi/c_api.h`.
- `KeyboardExtension/IosPinyinCoreBridge.swift` owns the C ABI engine/session handles.
- `KeyboardExtension/KeyboardViewController.swift` renders the candidate bar, QWERTY rows, Globe key, symbols toggle, Chinese/English toggle, Space, Delete, and Return.
- `KeyboardExtension/Info.plist` sets `RequestsOpenAccess` to `false`.
- `ContainerApp/IosSettingsStore.swift` creates a shared App Group settings file and keeps user learning off until the user opts in.

## Build

Install the simulator Rust target once:

```bash
rustup target add aarch64-apple-ios-sim
```

Then build the Rust static library and iOS app:

```bash
bash scripts/build_ios_keyboard.sh
```

The script builds `private_pinyin_ime_ffi` as a static library and then runs `xcodebuild` for the `PrivatePinyin` scheme. It defaults to `IOS_DEPLOYMENT_TARGET=18.0`.
For local signing/App Group experiments, the simulator build also accepts
`PRIVATE_PINYIN_IOS_APP_BUNDLE_ID`,
`PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID`, and
`PRIVATE_PINYIN_IOS_APP_GROUP_ID`, defaulting to the checked-in scaffold values.

Before manual keyboard testing, run the automated readiness checks:

```bash
bash scripts/run_ios_smoke_readiness.sh
```

This builds the simulator app and verifies the produced app/extension bundle
identifiers, App Group ID expansion, `RequestsOpenAccess=false`, bundled default
settings, and Keyboard Extension no-network source posture.

## App Store Archive

Stage 14 makes signing identifiers explicit. Copy
`AppStoreMetadata/Signing.env.example` to the ignored `Signing.env`, copy
`AppStoreMetadata/ExportOptions.plist.template` to the ignored
`ExportOptions.plist`, fill in the Apple team ID, bundle IDs, App Group ID, and
provisioning profile names, then run:

```bash
. platform/ios_keyboard/AppStoreMetadata/Signing.env
bash scripts/package_ios_app_store.sh
```

The script requires device signing/provisioning and writes the archive under
`dist/ios/PrivatePinyin.xcarchive`. It fails before archiving unless the export
options plist contains provisioning profile entries for both the container app
bundle ID and keyboard extension bundle ID.

For TestFlight upload, copy `AppStoreMetadata/ExportOptions.upload.plist.template`
to the ignored `ExportOptions.plist`, configure the App Store Connect API key
variables in `Signing.env`, then run the same package script. The script writes
`dist/ios/package_summary.txt`; update `docs/ios_testflight_upload_record.md`
with the App Store Connect build number and processing status after upload.

## Local Smoke Test

Use the shared record template in `../../docs/platform_smoke_test_plan.md` when validating release-readiness behavior.

1. Install and run the container app on an iOS simulator.
2. Tap `打开系统设置` in the container app.
3. Open `通用 > 键盘 > 键盘 > 添加新键盘` and select `猫栈拼音`.
4. Open Notes, switch to `猫栈拼音` with the Globe key, type `nihao`, and tap `你好` in the candidate bar.

The container app deliberately uses `UIApplication.openSettingsURLString`. Do
not replace it with a private `App-Prefs` URL: private Settings deep links may
break across iOS releases and create App Store review risk.
5. Type `jintian`, tap `今天`, and confirm prediction candidates such as `天气` remain visible after commit.
6. Confirm Full Access remains off.
7. In the container app, enable Learn selected candidates, type/select a candidate again, and confirm the keyboard still works with the shared settings path.
8. Open the keyboard's inline preferences, switch `输出字形` to `繁體`, and confirm `limian` displays and commits `裡面`; switch back to `简体` and confirm `里面` returns.
9. Enter pinyin with more than three results and swipe the candidate strip to confirm up to nine candidates in the group remain selectable before using the fixed next-group control.
10. Open `123`, then `#+=`, and verify the extended symbol rows match the requested bracket/operator/book-title/punctuation set; tap `123` to return to the original numeric page.

The Simplified/Traditional option uses the local system Chinese transform for
candidate display, predictions, and committed text. It does not use a network
service or duplicate the normalized core lexicon and learning records. The
result is generic, best-effort Traditional Chinese rather than complete Taiwan
or Hong Kong vocabulary localization. Phrase-aware examples such as `头发 -> 頭髮`
and `面条 -> 麵條` are regression-tested, but ambiguous vocabulary may still
need a dedicated approved conversion dictionary in a future stage.

Password and phone-number fields are expected to fall back to the system keyboard by iOS policy.

## Privacy Notes

- The keyboard extension does not request Full Access.
- The keyboard extension does not use network APIs.
- User learning is disabled by default on iOS and must be enabled in the container app.
- When App Group entitlements are active, settings and learned lexicon files live under the configured `PRIVATE_PINYIN_IOS_APP_GROUP_ID` value, defaulting to `group.com.privatepinyin.ios` for local scaffolding.
- If App Group storage is unavailable, the learning toggle stays disabled rather than writing learned data into a private, extension-only sandbox.
- If the keyboard extension cannot open shared settings while Full Access is off, it falls back to built-in defaults so typing still works without learning.
- The container app can clear local lexicon artifacts, including SQLite WAL/SHM sidecar files.

## Known Gaps

- App Store archive/export hooks, signing env templates, and App Group build-setting wiring are present, but owner signing/provisioning values are not committed.
- Production signing/provisioning must enable the same App Group configured through `PRIVATE_PINYIN_IOS_APP_GROUP_ID` before release.
- The simulator build requires the Rust iOS target to be installed locally.
- Real Notes/Safari/password-field smoke testing still needs an iOS simulator or device pass.
