# Changelog

## Unreleased

### Added

- Initialized the repository documentation and project skeleton.
- Added the development specification, progress tracker, decision log, and open item tracker.
- Added pull request workflow and privacy review checklist.
- Added the stage-01 Rust workspace with `ime_core` and `tools/test_cli`.
- Added `InputSession`, `KeyEvent`, `ImeOutput`, `Candidate`, basic pinyin parsing, embedded sample lexicon lookup, and simple candidate ranking.
- Added parser, candidate, ranking, prediction-placeholder, and privacy tests.
- Added minimal GitHub Actions for Rust formatting, clippy, and tests.
- Added input guardrails for maximum raw pinyin length, system-modifier passthrough, punctuation commits, and no-candidate space fallback.
- Added a guard so Enter without active raw input remains idle instead of committing an empty string.
- Added SQLite-backed user lexicon persistence for selected candidates.
- Added local bigram prediction after candidate commits.
- Added learning controls for `enable_user_learning` and `strict_privacy_mode`.
- Added tests for prediction, user lexicon persistence, disabled learning, and strict privacy mode.
- Added the stage-03 C ABI crate, public `ffi/c_api.h`, C demo, and Swift/C++ integration notes.
- Added FFI tests for engine/session creation, key input, candidate reading, commit output, null-handle behavior, and output freeing.
- Added Rust and C layout assertions to catch C ABI/header drift.
- Added CI coverage for building and running the C ABI demo.
- Added the stage-04 Windows TSF prototype with C++ 20 DLL project, COM class factory, registration hooks, key-event bridge, composition updates, candidate popup, and local registration scripts.
- Added a Windows TSF source scaffold check to CI.
- Added the stage-05 macOS InputMethodKit prototype with Swift host code, IMKServer, IMKInputController, C ABI bridge, marked-text updates, candidate panel wiring, local build script, and install/uninstall scripts.
- Added a macOS IMK source scaffold check to CI.
- Added JSON settings loading and atomic settings writing for `ImeSettings`.
- Added C ABI support for host-provided settings paths, clearing the user lexicon, and exporting the user lexicon.
- Added `tools/settings_cli` for installer scripts to write settings, toggle strict privacy mode, clear the user lexicon, and export the user lexicon.
- Added a macOS input method menu settings entry for strict privacy mode, clearing/exporting the user lexicon, and opening the settings file.
- Added Windows settings initialization under `%LOCALAPPDATA%\PrivatePinyin` and a PowerShell settings window for privacy, learning, prediction, clear, and export actions.
- Added prototype installer packaging scripts for Windows and macOS, including an unsigned macOS `.pkg`, Windows zip staging, and WiX MSI source.
- Added a Stage 6 installer/settings scaffold check to CI.
- Added the stage-07 iOS Keyboard Extension prototype with a SwiftUI container app, `UIInputViewController` keyboard extension, candidate bar, QWERTY layout, Globe key, symbols toggle, and Chinese/English toggle.
- Added iOS C ABI module-map wiring so the keyboard extension can link the Rust core as an iOS static library.
- Added iOS build and scaffold-check scripts, including plist validation for `RequestsOpenAccess=false` and source scanning for network APIs.
- Added Stage 08 platform validation planning with Windows, macOS, and iOS smoke-test record templates.
- Added Windows Rust test and TSF compile coverage to GitHub Actions with a `windows-latest` job.
- Added a Stage 08 validation scaffold check script.
- Added Rust build caching to CI.

### Changed

- Tightened initialization guidance for Rust lockfile handling, Xcode ignores, runtime data paths, Stage 1 workspace layout, and CI expectations.
- Updated README instructions for the Rust workspace and CLI smoke test.
- Updated the stage delivery workflow to use local review before GitHub push and merge.
- Changed candidate ordering to rank exact matches before prefix matches, then sort within each group by frequency.
- Merged user lexicon candidates ahead of base lexicon duplicates.
- Reused one SQLite connection per user lexicon instead of reopening the database on every lookup or learning write.
- Deduplicated compact pinyin normalization across base and user lexicon lookup.
- Documented Stage 03 C ABI null-return, memory ownership, and non-thread-safe handle contracts.
- Documented Windows TSF build, registration, and manual Notepad smoke-test workflow.
- Changed Windows TSF key handling so Ctrl/Alt/Win shortcuts pass through, idle editing keys are not swallowed, and Shift-modified text keys stay with the host.
- Changed Windows TSF focus handling to hide prediction candidates and clear host input state when focus leaves the text service.
- Changed Windows TSF composition cleanup to reset the Rust session when focus loss or external composition termination clears host-side state.
- Documented macOS IMK local build, install, uninstall, and manual TextEdit smoke-test workflow.
- Documented Stage 6 installer packaging and settings workflows for Windows and macOS.
- Changed desktop hosts to pass settings paths into the shared C ABI instead of using only built-in defaults.
- Documented iOS build, simulator smoke-test, and privacy-default workflows.
- Extended the development specification with release-preparation stages 8 through 12.

### Fixed

- Fixed idle Space so prediction candidates no longer hijack normal space input.
- Fixed unhandled keys during active composition so hosts keep the current preedit and candidates instead of treating idle output as cleared state.
- Fixed macOS Shift+digit handling so shifted number keys pass through to the host instead of selecting candidates.
- Fixed the stage-03 reserved `config_json_path` so non-null paths now load settings snapshots.
- Fixed the prototype Windows MSI template so TSF registration runs as a per-user install instead of writing HKCU registration under the SYSTEM account.
- Fixed SQLite user lexicon connections to use WAL and a busy timeout for multi-process desktop host writes.
- Fixed user lexicon export so engines without a configured user lexicon still write an empty TSV with headers.
- Fixed invalid numeric settings so zero values clamp to defaults without discarding the rest of the settings snapshot.
- Fixed iOS symbol-key handling so active composition state stays synchronized with the shared Rust engine.
- Fixed iOS self-triggered text-change handling so candidate commits can keep prediction candidates and engine context.
- Fixed iOS Chinese-mode Shift+letter handling so shifted letters insert uppercase text instead of entering pinyin composition.

### Security and Privacy

- Documented the default no-network, no-telemetry, no-account, no-cloud-sync privacy posture.
- Clarified that error logs must not embed user input, pinyin input, candidates, or committed text.
- Ensured strict privacy mode and disabled learning skip SQLite learning writes.
- Ensured strict privacy mode disables user learning when settings snapshots are loaded or written.
