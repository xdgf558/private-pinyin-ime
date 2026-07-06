# Development Progress

Last updated: 2026-07-06 18:22
Current stage: stage-05
Current status: completed

## Stage Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| 01 | Rust core engine | completed | 2026-07-06 12:12 | Core engine, CLI, tests, and CI are ready for local review |
| 02 | User lexicon and prediction | completed | 2026-07-06 15:01 | Merged to `main` through PR #3 |
| 03 | C ABI and CLI integration | completed | 2026-07-06 15:53 | Merged to `main` through PR #4 |
| 04 | Windows TSF prototype | completed | 2026-07-06 17:00 | Merged to `main`; Windows smoke test still required |
| 05 | macOS InputMethodKit prototype | completed | 2026-07-06 18:22 | Swift IMK app bundle prototype, C ABI bridge, marked text, candidate panel, and local build/install scripts are ready for local review |
| 06 | Installers and settings | not_started | | Depends on desktop prototypes |
| 07 | iOS keyboard extension | not_started | | Planned after desktop MVP |

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

## Current Work

- Stage 05 is complete on local branch `codex/stage-05-macos-imk`.
- Awaiting local review before pushing to GitHub.

## Validation Results

- Command: `cargo fmt --check`
- Result: passed
- Notes: Formatting is clean after the stage-05 macOS IMK prototype.

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: No clippy warnings after the stage-05 macOS IMK prototype.

- Command: `cargo test --workspace`
- Result: passed
- Notes: 32 integration tests passed after the stage-05 review fixes.

- Command: `cargo run -p test_cli -- nihao`
- Result: passed
- Notes: Output includes `你好`.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: C layout assertions compiled and ran; C demo created an engine, fed `nihao`, read first candidate `你好`, and committed `你好`.

- Command: `bash scripts/check_windows_tsf_sources.sh`
- Result: passed
- Notes: Source scaffold includes the CMake project, COM DLL exports, TSF key sink, C ABI bridge, candidate window, and registration scripts.

- Command: `bash scripts/check_macos_imk_sources.sh`
- Result: passed
- Notes: Source scaffold includes Swift IMK source files, C ABI bridge, `IMKServer`, `IMKInputController`, `IMKCandidates`, bundle plist, and install scripts.

- Command: `bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin.app` with embedded `libprivate_pinyin_ime.dylib` and ad-hoc signing.

- Command: `codesign --verify --deep --strict --verbose=2 dist/macos_imk/PrivatePinyin.app`
- Result: passed
- Notes: The local macOS app bundle is valid on disk with ad-hoc signing.

- Command: `otool -L dist/macos_imk/PrivatePinyin.app/Contents/MacOS/PrivatePinyin`
- Result: passed
- Notes: The executable loads the Rust FFI dylib through `@rpath/libprivate_pinyin_ime.dylib`.

- Command: `leaks --atExit -- target/debug/ime_c_demo`
- Result: not completed
- Notes: macOS `leaks` could not get the child process task port in the current sandbox; this was not rerun as part of the review fix.

- Command: `git diff --check`
- Result: passed
- Notes: No whitespace errors.

## Open Items

- Select the final project license before external reuse or release.
- Replace sample lexicon data with licensed production lexicon data before release.
- Keep production runtime data outside source directories.
- Add indexed lexicon lookup before production dictionary scale.
- Refine Shift toggle semantics in platform hosts.
- Implement candidate paging in a later stage.
- Commit first candidate before punctuation during composition.
- Use range-prefix SQLite queries for indexed user lexicon prefix lookup.
- Preserve exact user lexicon matches before applying query limits.
- Fuse user and base ranking instead of unconditional user-first ordering.
- Wire sanitized user lexicon database failures into logging.
- Expose user lexicon path, learning controls, and strict privacy mode through the C ABI settings loader.
- Add Windows code signing for TSF DLL and installer.
- Build production Windows installer and uninstaller.
- Polish Windows candidate window for high DPI, dark mode, and paging.
- Validate TSF DLL loading and Notepad smoke test on Windows 11.
- Position the Windows candidate popup with `ITfContextView::GetTextExt`.
- Unregister the Windows candidate window class on DLL unload.
- Add TSF display attributes for preedit text.
- Add Windows CI compile coverage for the TSF host.
- Add macOS code signing and notarization.
- Build production macOS installer and uninstaller package.
- Polish macOS candidate positioning and appearance.
- Add macOS settings entry and menu icon assets.
- Verify IMK candidate panel number-key routing on macOS.

## Files Changed In Latest Stage

- `README.md`
- `CHANGELOG.md`
- `.github/workflows/rust.yml`
- `docs/DEVELOPMENT_PROGRESS.md`
- `docs/DECISIONS.md`
- `docs/OPEN_ITEMS.md`
- `docs/macos_inputmethodkit_notes.md`
- `platform/macos_imk/`
- `scripts/README.md`
- `scripts/build_macos_imk.sh`
- `scripts/check_macos_imk_sources.sh`

## Next Step

- Review stage-05 locally; after approval, push and merge through GitHub.
