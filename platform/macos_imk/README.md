# macOS InputMethodKit Host

This directory contains the stage-05 macOS InputMethodKit prototype.

The macOS host remains thin:

- Convert IMK key and modifier events into core `ImeKeyEvent` values.
- Use marked text for composition.
- Render candidates through the system `IMKCandidates` panel.
- Commit selected text through the active `IMKTextInput` client.
- Reset Rust session state when focus, deactivation, or external composition termination invalidates host state.

## Layout

- `Sources/`: Swift IMK host and C ABI bridge.
- `Resources/Info.plist`: input method app bundle metadata.
- `installer/install-local.sh`: copies the built app into `~/Library/Input Methods`.
- `installer/uninstall-local.sh`: removes the local input method app.

## Build

```bash
bash scripts/build_macos_imk.sh
```

The script builds `ffi/ime_ffi`, compiles the Swift host, embeds `libprivate_pinyin_ime.dylib`, and writes:

```text
dist/macos_imk/PrivatePinyin.app
```

## Install Locally

```bash
platform/macos_imk/installer/install-local.sh
```

Then open System Settings > Keyboard > Input Sources and add PrivatePinyin.

## Uninstall Locally

```bash
platform/macos_imk/installer/uninstall-local.sh
```

## Manual Smoke Test

1. Open TextEdit.
2. Switch to PrivatePinyin.
3. Type `zhongguo`, press `Space`, and confirm `中国` commits.
4. Type `nihao`, confirm candidates appear near the insertion point, and select one with a number key.
5. Press standalone `Shift` to toggle mode; `Shift+A` should pass through as uppercase input.

## Known Gaps

- Local builds are ad-hoc signed only.
- Release packaging, Developer ID signing, and notarization are tracked for later stages.
- Candidate panel appearance and positioning need app-by-app validation.
- Custom menu icon and preferences UI are not included yet.
