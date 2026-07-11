# macOS InputMethodKit Notes

Stage 5 implements the macOS InputMethodKit host prototype.

## Target

- macOS 14 or newer.
- Swift with Objective-C bridge where needed.
- InputMethodKit app bundle.
- Calls the shared Rust core through the C ABI.
- Local build script that creates `dist/macos_imk/PrivatePinyin.app`.

## Required References

- Apple InputMethodKit documentation.

## Constraints

- Use marked text for composition.
- Candidate UI should follow the insertion point.
- Do not access the network by default.

## Implemented In Stage 05

- `IMKServer` startup from a Swift app entry point.
- `IMKInputController` subclass for key handling, composition updates, candidate selection, activation/deactivation cleanup, and external composition commits.
- Swift C ABI bridge around `ime_engine_new`, `ime_session_feed_key`, `ime_session_commit_candidate`, and `ime_session_reset`.
- IMK marked text via `updateComposition()` and committed text through the active `IMKTextInput` client.
- One process-scoped `IMKCandidates` panel shared by all client controllers, with numeric candidate selection through the Rust core. The panel is attached to the process-level `IMKServer` and must outlive individual client sessions.
- Standalone app bundle build script plus local install/uninstall scripts.

## Manual macOS Smoke Test

1. Build with `bash scripts/build_macos_imk.sh`.
2. Install with `platform/macos_imk/installer/install-local.sh`.
3. Open System Settings > Keyboard > Input Sources and add 猫栈拼音.
4. In TextEdit, type `zhongguo`, press `Space`, and confirm `中国` commits.
5. Type `nihao`, confirm candidates follow the insertion point, and select a candidate with a number key.
6. Press standalone `Shift` to toggle mode, then press `Shift+A` and confirm uppercase input passes through.
7. With candidates alternately visible and committed, switch among TextEdit, Safari, and Chrome at least 20 times; confirm input still works and no new `PrivatePinyin-*.ips` crash report appears.
