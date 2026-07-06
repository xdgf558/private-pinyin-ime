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

## Local Smoke Test

Use the shared record template in `../../docs/platform_smoke_test_plan.md` when validating release-readiness behavior.

1. Install and run the container app on an iOS simulator.
2. Open Settings > General > Keyboard > Keyboards.
3. Add PrivatePinyin.
4. Open Notes, switch to PrivatePinyin with the Globe key, type `nihao`, and tap `你好` in the candidate bar.
5. Type `jintian`, tap `今天`, and confirm prediction candidates such as `天气` remain visible after commit.
6. Confirm Full Access remains off.
7. In the container app, enable Learn selected candidates, type/select a candidate again, and confirm the keyboard still works with the shared settings path.

Password and phone-number fields are expected to fall back to the system keyboard by iOS policy.

## Privacy Notes

- The keyboard extension does not request Full Access.
- iOS sources do not use network APIs.
- User learning is disabled by default on iOS and must be enabled in the container app.
- When App Group entitlements are active, settings and learned lexicon files live under `group.com.privatepinyin.ios`.
- If App Group storage is unavailable, the learning toggle stays disabled rather than writing learned data into a private, extension-only sandbox.
- If the keyboard extension cannot open shared settings while Full Access is off, it falls back to built-in defaults so typing still works without learning.
- The container app can clear local lexicon artifacts, including SQLite WAL/SHM sidecar files.

## Known Gaps

- App Store signing and provisioning are not configured.
- App Group identifiers are present in source entitlements, but production signing/provisioning must enable the same group before release.
- The simulator build requires the Rust iOS target to be installed locally.
- Real Notes/Safari/password-field smoke testing still needs an iOS simulator or device pass.
