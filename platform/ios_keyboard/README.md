# iOS Keyboard Extension

This directory contains the stage-07 iOS container app and custom keyboard extension.

The iOS host remains thin:

- `PrivatePinyin.xcodeproj` builds a SwiftUI container app plus a `UIInputViewController` keyboard extension.
- `PrivatePinyinC/module.modulemap` imports the shared C ABI from `ffi/c_api.h`.
- `KeyboardExtension/IosPinyinCoreBridge.swift` owns the C ABI engine/session handles.
- `KeyboardExtension/KeyboardViewController.swift` renders the candidate bar, QWERTY rows, Globe key, symbols toggle, Chinese/English toggle, Space, Delete, and Return.
- `KeyboardExtension/Info.plist` sets `RequestsOpenAccess` to `false`.

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

1. Install and run the container app on an iOS simulator.
2. Open Settings > General > Keyboard > Keyboards.
3. Add PrivatePinyin.
4. Open Notes, switch to PrivatePinyin with the Globe key, type `nihao`, and tap `你好` in the candidate bar.
5. Confirm Full Access remains off.

Password and phone-number fields are expected to fall back to the system keyboard by iOS policy.

## Privacy Notes

- Stage 07 does not request Full Access.
- Stage 07 iOS sources do not use network APIs.
- The container app can clear local lexicon artifacts in its own app container.
- Shared user lexicon storage through App Groups is deferred until the user explicitly opts in.

## Known Gaps

- App Store signing, entitlements, and provisioning are not configured.
- App Group storage is not configured.
- The simulator build requires the Rust iOS target to be installed locally.
- Real Notes/Safari/password-field smoke testing still needs an iOS simulator or device pass.
