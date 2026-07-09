# macOS InputMethodKit Host

This directory contains the macOS InputMethodKit prototype.

The macOS host remains thin:

- Convert IMK key and modifier events into core `ImeKeyEvent` values.
- Use marked text for composition.
- Render candidates through the system `IMKCandidates` panel.
- Commit selected text through the active `IMKTextInput` client.
- Reset Rust session state when focus, deactivation, or external composition termination invalidates host state.
- Load a settings snapshot from `~/Library/Application Support/PrivatePinyin/settings.json`.
- Expose a menu settings entry for strict privacy mode, clearing the user lexicon, exporting the user lexicon, and opening the JSON settings file.

## Layout

- `Sources/`: Swift IMK host and C ABI bridge.
- `Resources/Info.plist`: input method app bundle metadata.
- `installer/install-local.sh`: copies the built app into `~/Library/Input Methods`.
- `installer/uninstall-local.sh`: removes the local input method app.
- `../../scripts/package_macos_pkg.sh`: creates a `.pkg` installer and optionally signs/notarizes it for release candidates.

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

Then open System Settings > Keyboard > Input Sources and add 猫栈拼音.

## Build Package

```bash
bash scripts/package_macos_pkg.sh
```

The package is written to:

```text
dist/macos_imk/PrivatePinyin-0.1.10.pkg
```

The installer includes a post-install onboarding window. After installation it
opens PrivatePinyin Setup in the active user session, with a button for Keyboard
Settings and the steps needed to add the input source.

If an older PrivatePinyin input method process is already running during an
upgrade install, macOS may activate the existing process instead of passing the
onboarding flag to the new app. In that case, open the app manually, re-open
System Settings, or logout/login before adding the input source.

Install with:

```bash
sudo installer -pkg dist/macos_imk/PrivatePinyin-0.1.10.pkg -target /
```

Release-candidate packages require Developer ID signing and notarization:

```bash
PRIVATE_PINYIN_MAC_APP_SIGN_IDENTITY="Developer ID Application: Example" \
PRIVATE_PINYIN_MAC_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Example" \
PRIVATE_PINYIN_NOTARY_PROFILE="private-pinyin-notary" \
bash scripts/package_macos_pkg.sh
```

## Uninstall Locally

```bash
platform/macos_imk/installer/uninstall-local.sh
```

## Manual Smoke Test

Use the shared record template in `../../docs/platform_smoke_test_plan.md` when validating release-readiness behavior.

1. Open TextEdit.
2. Confirm PrivatePinyin appears under Chinese/Simplified Chinese input sources and can be enabled.
3. Switch to PrivatePinyin.
4. Type `zhongguo`, press `Space`, and confirm `中国` commits.
5. Type `nihao`, confirm candidates appear near the insertion point, and select one with a number key.
6. Press standalone `Shift` to toggle mode; `Shift+A` should pass through as uppercase input.
7. Open the input method menu and toggle `严格隐私模式`.
8. Open `偏好设置...` from the input method menu and toggle prediction or learning.
9. Use the input method menu to `导出用户词库...` and `清空用户词库`.

## Known Gaps

- Local builds are ad-hoc signed unless `PRIVATE_PINYIN_MAC_APP_SIGN_IDENTITY` is provided.
- Developer ID signing and notarization hooks are present; release still requires owner credentials and notarization evidence.
- Candidate panel appearance and positioning need app-by-app validation.
- The menu bar/input-source icon uses the packaged template TIFF; the app bundle uses the packaged color icon.
