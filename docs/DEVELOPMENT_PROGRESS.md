# Development Progress

Last updated: 2026-07-07 07:45
Current stage: stage-11
Current status: completed

## Stage Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| 01 | Rust core engine | completed | 2026-07-06 12:12 | Core engine, CLI, tests, and CI are ready for local review |
| 02 | User lexicon and prediction | completed | 2026-07-06 15:01 | Merged to `main` through PR #3 |
| 03 | C ABI and CLI integration | completed | 2026-07-06 15:53 | Merged to `main` through PR #4 |
| 04 | Windows TSF prototype | completed | 2026-07-06 17:00 | Merged to `main`; Windows smoke test still required |
| 05 | macOS InputMethodKit prototype | completed | 2026-07-06 18:22 | Merged to `main` after local review |
| 06 | Installers and settings | completed | 2026-07-06 19:40 | Merged to `main` after local review |
| 07 | iOS keyboard extension | completed | 2026-07-06 20:44 | iOS container app, Keyboard Extension, C ABI static-library wiring, candidate bar, Globe key, and privacy-default scaffold are ready for local review |
| 08 | Platform validation and CI hardening | completed | 2026-07-06 21:57 | Windows Rust test and TSF compile CI, platform smoke-test records, release-readiness validation checks, and Stage 9-12 planning are ready for local review |
| 09 | Core production hardening | completed | 2026-07-06 23:04 | Merged to `main` through PR #8 |
| 10 | Platform host polish | completed | 2026-07-06 23:14 | Merged to `main` through PR #9 |
| 11 | Settings, privacy, and iOS storage closure | completed | 2026-07-07 07:45 | Shared default template use, stronger settings/export writes, hidden CapsLock platform UI, iOS App Group settings storage, learning opt-in, mode derivation, Globe-key visibility, review fixes, and Stage 11 checks are ready for local review |

## Completed Work

- Created the initial repository skeleton.
- Added the project development specification under `docs/`.
- Added progress, changelog, decision, and open item tracking files.
- Added platform and tool placeholder directories.
- Added a pull request template with privacy review checks.
- Addressed initialization PR review feedback for ignore rules, privacy logging, sample data provenance, and Stage 1 workflow expectations.
- Implemented the stage-01 Rust workspace and `ime_core` crate.
- Implemented `InputSession`, `KeyEvent`, `ImeOutput`, `Candidate`, basic pinyin parsing, embedded sample lexicon lookup, and simple ranking.
- Added `tools/test_cli` and minimal GitHub Actions for Rust validation.
- Addressed local review feedback for raw input limits, modifier-key passthrough, punctuation commits, no-candidate space fallback, and exact-before-prefix ranking.
- Addressed local review feedback so idle Enter does not commit an empty string.
- Implemented the stage-02 SQLite user lexicon and local bigram prediction.
- Added commit learning for selected candidates, plus `enable_user_learning` and `strict_privacy_mode` write guards.
- Added tests for `jintian -> 今天 -> 天气`, user lexicon persistence, disabled learning, and strict privacy mode.
- Addressed stage-02 review feedback so idle Space commits a normal space while digit keys select prediction candidates.
- Reused one mutex-protected SQLite connection per user lexicon instance instead of reopening the database for each lookup or learning write.
- Recorded follow-up open items for SQLite prefix range queries, exact-match preservation before query limits, user/base ranking fusion, and sanitized DB error logging.
- Deduplicated compact pinyin normalization across base and user lexicon lookup.
- Merged stage 02 to `main` through GitHub PR #3.
- Implemented the stage-03 `ffi/ime_ffi` crate that exposes `libprivate_pinyin_ime`.
- Added `ffi/c_api.h`, output ownership rules, C demo, Swift/C++ integration notes, and C ABI CI coverage.
- Added FFI tests for engine/session creation, `nihao` input, candidate reading, commit output, null-handle behavior, and output freeing.
- Addressed stage-03 review feedback by documenting NULL-return, non-thread-safe handle, and output ownership contracts in the C ABI.
- Added Rust layout assertions and C `_Static_assert` checks to catch header/ABI drift in CI.
- Recorded a follow-up open item for exposing user lexicon path, learning controls, and strict privacy mode through C ABI settings loading.
- Merged stage 03 to `main` through GitHub PR #4.
- Implemented the stage-04 Windows TSF C++ DLL prototype under `platform/windows_tsf`.
- Added COM class factory, `DllRegisterServer`/`DllUnregisterServer`, TSF profile registration hooks, and local `regsvr32` scripts.
- Added `ITfTextInputProcessorEx`, `ITfKeyEventSink`, and `ITfCompositionSink` host wiring for activation, key handling, composition updates, candidate display, and commit output.
- Added a thin C ABI bridge from Windows key events to the Rust core and a simple non-activating candidate popup.
- Added Windows build instructions, manual Notepad smoke-test steps, and a CI source scaffold check for TSF files.
- Addressed stage-04 review feedback so Windows TSF passes through Ctrl/Alt/Win shortcuts, avoids eating idle editing keys, and leaves Shift-modified text keys to the host.
- Recorded follow-up open items for TSF text-extent candidate positioning, window class unload cleanup, display attributes, and Windows CI compile coverage.
- Addressed stage-04 review feedback so Windows TSF hides prediction candidates and clears host active-input state on focus loss.
- Addressed stage-04 review feedback so Windows TSF resets the Rust session when focus loss or external composition termination invalidates host-side composition.
- Merged stage 04 to `main`.
- Implemented the stage-05 macOS InputMethodKit prototype under `platform/macos_imk`.
- Added Swift `IMKServer` startup and a `PrivatePinyinInputController` subclass for key handling, standalone Shift toggle, marked text, candidate selection, commit output, and cleanup.
- Added a Swift C ABI bridge around `ime_engine_new`, `ime_session_feed_key`, `ime_session_commit_candidate`, and `ime_session_reset`.
- Added `IMKCandidates` candidate panel wiring and local install/uninstall scripts for `~/Library/Input Methods`.
- Added `scripts/build_macos_imk.sh` to build an ad-hoc signed local `PrivatePinyin.app` bundle and `scripts/check_macos_imk_sources.sh` for CI scaffold checks.
- Recorded follow-up open items for macOS signing/notarization, packaged installer, candidate UI polish, and menu icon/settings UI.
- Addressed stage-05 review feedback so unhandled keys during active composition preserve current preedit/candidates instead of clearing host state.
- Addressed stage-05 review feedback so macOS Shift+digit passes through consistently with Windows, and recorded a follow-up for IMK candidate panel number-key routing validation.
- Implemented stage-06 JSON settings loading and atomic settings writing for `ImeSettings`.
- Wired `config_json_path` through the C ABI so desktop hosts can pass a settings snapshot path at engine creation.
- Added C ABI and Rust core APIs for clearing and exporting the user lexicon.
- Added `tools/settings_cli` for installer scripts to write defaults, toggle strict privacy mode, clear the user lexicon, and export the user lexicon.
- Added macOS settings menu actions for strict privacy mode, clearing/exporting the user lexicon, and opening the settings file.
- Added Windows settings initialization under `%LOCALAPPDATA%\PrivatePinyin` and a PowerShell settings window for privacy, learning, prediction, clear, and export actions.
- Added prototype packaging scripts for macOS `.pkg`, Windows installer staging zip, and optional WiX MSI generation.
- Added CI scaffold coverage for installer/settings files.
- Addressed stage-06 review feedback by changing the WiX MSI template to per-user install and user-context TSF registration.
- Addressed stage-06 review feedback by enabling SQLite WAL and a busy timeout for multi-process user lexicon writes.
- Addressed stage-06 review feedback so invalid numeric settings clamp to defaults without discarding other settings, and export without a configured user lexicon writes an empty TSV.
- Recorded follow-up open items for default settings drift, stronger Rust atomic file replacement, and CapsLock toggle support.
- Merged stage 06 to `main`.
- Implemented the stage-07 iOS container app and Keyboard Extension prototype under `platform/ios_keyboard`.
- Added a SwiftUI container app with a clear-local-lexicon action for app-container artifacts.
- Added a `UIInputViewController` keyboard extension with QWERTY rows, candidate bar, Globe key, symbols toggle, Chinese/English toggle, Space, Delete, and Return.
- Added an iOS C ABI bridge that creates the Rust engine/session, feeds key events, commits candidates, toggles mode, and frees outputs.
- Added `PrivatePinyinC/module.modulemap` and `scripts/build_ios_keyboard.sh` to link the Rust C ABI as an iOS static library.
- Added `RequestsOpenAccess=false` in the keyboard extension plist and CI scaffold checks for iOS privacy defaults and network API absence.
- Recorded follow-up open items for iOS App Store signing, App Group storage, user-facing permission explanation, simulator/device smoke tests, mode-state derivation, and Globe key visibility.
- Addressed stage-07 review feedback so iOS self-triggered text changes do not reset the Rust session, Chinese-mode Shift+letter inserts uppercase text, and mode-toggle UI state only changes after engine success.
- Merged stage 07 to `main`.
- Added stage-08 platform validation and CI hardening work.
- Added a pinned `windows-2022` GitHub Actions job that runs `cargo test --workspace`, runs `scripts/build_windows_tsf.ps1`, and compiles the Windows TSF DLL with MSVC/CMake.
- Added Rust build caching to CI.
- Added `docs/platform_smoke_test_plan.md` with manual smoke-test record templates for Windows 11 TSF, macOS InputMethodKit, and iOS Keyboard Extension, including focus/app-switch cleanup and multi-process learning regressions.
- Added `scripts/check_platform_validation_sources.sh` and wired it into CI.
- Extended the development specification with release-preparation stages 8 through 12.
- Linked platform READMEs to the shared smoke-test record template.
- Fixed CI feedback by pinning the Windows runner, making Windows COM declarations and DLL exports explicit, and adding a non-`rg` fallback to the iOS source scan.
- Closed `OI-022` for Windows Rust test and TSF compile CI coverage while keeping runtime smoke-test items open.
- Implemented stage-09 core production hardening.
- Changed base lexicon lookup to build a compact-pinyin sorted index and use binary prefix ranges.
- Changed SQLite user lexicon lookup to use compact-pinyin range queries and exact-row preservation before prefix limits.
- Added exact/prefix-aware user/base ranking fusion before deduplication.
- Implemented candidate paging by `candidate_page_size`, with PageUp/PageDown and ArrowUp/ArrowDown page movement.
- Changed composition punctuation to commit the first visible candidate plus punctuation, such as `你好,` for `nihao,`.
- Added sanitized log sink support and wired user lexicon lookup/learning failures to `error code=...` events.
- Added `docs/lexicon_data_policy.md` to keep production lexicon replacement gated on source/license approval.
- Added `scripts/check_stage09_core_sources.sh` and wired it into CI.
- Addressed stage-09 review feedback by constraining numeric selection to the visible candidate page, adding a SQLite `pinyin` index for exact user-lexicon lookup, documenting the compact-prefix upper-bound assumption, and recording host log callback work as `OI-041`.
- Closed `OI-006`, `OI-008`, `OI-009`, `OI-010`, `OI-011`, `OI-012`, and `OI-013`; kept `OI-001` open for licensed production data selection.
- Merged stage 09 to `main` through GitHub PR #8.
- Implemented stage-10 platform host polish.
- Changed Windows TSF candidate popup positioning to use `ITfContextView::GetTextExt` inside the edit session, with a caret fallback when text extents are unavailable.
- Added DPI-aware sizing, Windows app light/dark theme colors, monitor work-area clamping, and one-time window-class registration/unregistration for the Windows candidate popup.
- Added a macOS InputMethodKit Preferences window for strict privacy, prediction, and user learning toggles, with input-engine reload after settings changes.
- Addressed stage-10 review feedback by making the macOS preferences window a shared process-wide controller and broadcasting settings changes to all active input controllers.
- Added `scripts/check_stage10_platform_host_sources.sh` and wired it into CI.
- Closed `OI-017`, `OI-019`, and `OI-020`; kept TSF display attributes, custom macOS menu icon assets, and real platform smoke validation open.
- Merged stage 10 to `main`.
- Implemented stage-11 settings, privacy, and iOS storage closure.
- Added a shared Rust `AtomicFile` helper and moved settings JSON writes plus user lexicon TSV exports away from remove+rename.
- Added a Rust test that keeps `config/default_settings.json` aligned with `ImeSettings::default`.
- Changed Windows, macOS, and iOS default settings initialization to read packaged `default_settings.json` and patch only platform-local user lexicon paths.
- Added iOS App Group entitlements for the container app and keyboard extension, and made the shared settings/user-lexicon path available to both targets.
- Added iOS container-app controls and copy for Full Access, no-network behavior, App Group storage, local learning opt-in, and lexicon clearing.
- Changed the iOS keyboard extension to pass the settings path into `ime_engine_new`, derive mode UI from `ImeOutput.mode`, and hide the Globe key when `needsInputModeSwitchKey` is false.
- Added `scripts/check_stage11_settings_privacy_sources.sh` and wired it into CI.
- Closed `OI-032`, `OI-033`, `OI-034`, `OI-036`, `OI-037`, `OI-039`, and `OI-040`; kept iOS simulator/device smoke validation open as `OI-038`.
- Addressed stage-11 review feedback so the iOS keyboard falls back to the built-in engine if shared settings or App Group storage cannot be opened, and expanded `OI-038` to explicitly verify `RequestsOpenAccess=false` App Group behavior on device/simulator.
- Addressed stage-11 review feedback by pinning the `"user_lexicon_path": null` default-template format in the Stage 11 source check so Windows template patching cannot silently lose learning after JSON reformatting.

## Current Work

- Stage 11 is complete on local branch `codex/stage-11-settings-privacy-ios-storage`.
- Awaiting local review before pushing to GitHub.

## Validation Results

- Command: `cargo fmt --check`
- Result: passed
- Notes: Formatting is clean after the stage-11 settings/privacy changes.

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: No clippy warnings in the Rust workspace.

- Command: `cargo test --workspace`
- Result: passed
- Notes: 49 integration and ABI layout tests passed, including the new packaged default-settings template alignment check and settings overwrite check.

- Command: `cargo run -p test_cli -- nihao`
- Result: passed
- Notes: Output includes `你好`.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: C layout assertions compiled and ran; C demo created an engine, fed `nihao`, read first candidate `你好`, and committed `你好`.

- Command: `bash scripts/check_windows_tsf_sources.sh`
- Result: passed
- Notes: Source scaffold includes the CMake project, COM DLL exports, TSF key sink, C ABI bridge, settings path setup, registration scripts, settings UI script, WiX source, TSF text-extent popup anchoring, DPI/theme handling, and candidate window-class cleanup.

- Command: `bash scripts/check_macos_imk_sources.sh`
- Result: passed
- Notes: Source scaffold includes Swift IMK source files, C ABI bridge, settings store, preferences window, `IMKServer`, `IMKInputController`, `IMKCandidates`, bundle plist, and install/package scripts.

- Command: `bash scripts/check_installers_settings_sources.sh`
- Result: passed
- Notes: Installer/settings scaffold files are present, parseable, and desktop hosts reference packaged `default_settings.json`.

- Command: `bash scripts/check_ios_keyboard_sources.sh`
- Result: passed
- Notes: iOS scaffold includes App Group entitlements, shared settings store, template resources, `RequestsOpenAccess=false`, C ABI settings-path wiring, mode derivation, Globe visibility handling, and no Swift network API usage.

- Command: `bash scripts/check_platform_validation_sources.sh`
- Result: passed
- Notes: Stage 8 validation scaffold includes Windows Rust test CI, Windows TSF compile CI wiring, Rust caching, and Windows/macOS/iOS smoke-test record templates.

- Command: `bash scripts/check_stage09_core_sources.sh`
- Result: passed
- Notes: Stage 9 core hardening scaffold includes indexed lookup, pinyin and compact-pinyin user-lexicon indexes, range user-lexicon queries, ranking fusion, paging, punctuation behavior, sanitized logging, and lexicon data policy.

- Command: `bash scripts/check_stage10_platform_host_sources.sh`
- Result: passed
- Notes: Stage 10 host polish scaffold includes Windows TSF text-extent anchoring, DPI/theme-aware candidate popup rendering, window-class unregistering, and the shared macOS preferences window.

- Command: `bash scripts/check_stage11_settings_privacy_sources.sh`
- Result: passed
- Notes: Stage 11 scaffold includes default-template alignment and format pinning, shared AtomicFile writes, hidden CapsLock platform UI, iOS App Group entitlements, settings fallback, learning opt-in, mode derivation, and Globe-key checks.

- Command: `bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin.app` with the preferences window, bundled `default_settings.json`, embedded Rust FFI dylib, and ad-hoc signing.

- Command: `bash scripts/package_macos_pkg.sh`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.0.pkg`; the sandboxed first run could not write the pkg artifact, and the authorized rerun passed.

- Command: `bash scripts/build_ios_keyboard.sh`
- Result: passed
- Notes: Built the Rust C ABI for `aarch64-apple-ios-sim` with iOS deployment target 18.0, then compiled the unsigned simulator `PrivatePinyin.app` with embedded `PrivatePinyinKeyboard.appex`, App Group entitlements, settings fallback, and `default_settings.json` resources; sandboxed first run could not reach Xcode/CoreSimulator services, and the authorized rerun passed.

- Command: `windows-2022 CI: cargo test --workspace + scripts/build_windows_tsf.ps1`
- Result: not run locally
- Notes: Windows-only Rust tests plus MSVC/CMake TSF build are wired into the pinned `windows-2022` CI job and will be verified by GitHub Actions after the stage branch is pushed.

## Open Items

- Select the final project license before external reuse or release.
- Replace sample lexicon data with licensed production lexicon data before release.
- Keep production runtime data outside source directories.
- Refine Shift toggle semantics in platform hosts.
- Add Windows code signing for TSF DLL and installer.
- Build production Windows installer and uninstaller.
- Validate TSF DLL loading and Notepad smoke test on Windows 11.
- Add TSF display attributes for preedit text.
- Add macOS code signing and notarization.
- Build production macOS installer and uninstaller package.
- Polish macOS candidate positioning and appearance.
- Add custom macOS menu icon assets.
- Verify IMK candidate panel number-key routing on macOS.
- Add automatic update strategy.
- Validate Windows installer and settings UI on Windows 11.
- Configure iOS App Store signing and provisioning.
- Run iOS simulator smoke tests in Notes, Safari, and password fields, including whether `jintian -> 今天` keeps prediction candidates after commit and whether learning opt-in/App Group storage work under provisioning.
- Expose sanitized core logging through host ABI callbacks.

## Files Changed In Latest Stage

- `.github/workflows/rust.yml`
- `README.md`
- `CHANGELOG.md`
- `docs/DECISIONS.md`
- `docs/DEVELOPMENT_PROGRESS.md`
- `docs/OPEN_ITEMS.md`
- `docs/platform_smoke_test_plan.md`
- `docs/private_pinyin_ime_development_spec.md`
- `ime_core/src/atomic_file.rs`
- `ime_core/src/lib.rs`
- `ime_core/src/settings.rs`
- `ime_core/src/user_lexicon.rs`
- `ime_core/tests/settings_tests.rs`
- `platform/ios_keyboard/ContainerApp/ContentView.swift`
- `platform/ios_keyboard/ContainerApp/IosSettingsStore.swift`
- `platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements`
- `platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift`
- `platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift`
- `platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements`
- `platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj`
- `platform/ios_keyboard/README.md`
- `platform/macos_imk/Sources/SettingsStore.swift`
- `platform/windows_tsf/installer/open-settings.ps1`
- `platform/windows_tsf/src/core_bridge.cpp`
- `scripts/build_macos_imk.sh`
- `scripts/check_installers_settings_sources.sh`
- `scripts/check_ios_keyboard_sources.sh`
- `scripts/check_stage11_settings_privacy_sources.sh`
- `scripts/README.md`

## Next Step

- Review stage-11 locally; after approval, push and merge through GitHub.
