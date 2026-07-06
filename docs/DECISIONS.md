# Technical Decisions

## Decision 001: Core engine language

Date: 2026-07-06
Status: accepted
Decision: Use Rust for the shared IME core.
Reason: Memory safety, cross-platform library support, and good FFI support.
Consequences: Platform hosts call Rust through a C ABI.

## Decision 002: Stage delivery workflow

Date: 2026-07-06
Status: accepted
Decision: Deliver each development stage through a local review branch before pushing to GitHub and merging to `main`.
Reason: The project owner wants to inspect and request fixes locally before any stage branch is pushed for final GitHub merge.
Consequences: Codex should create a stage branch, commit scoped changes locally, provide a local review summary, fix feedback on the same branch, and only push and merge after approval.

## Decision 003: Rust workspace layout

Date: 2026-07-06
Status: accepted
Decision: Use a root Cargo workspace with `ime_core` for the engine and `tools/test_cli` for the CLI package.
Reason: Keeping the core and CLI in one workspace allows shared validation commands, a committed `Cargo.lock`, and reproducible CLI and release builds.
Consequences: Stage 1 should create the root `Cargo.toml`, commit `Cargo.lock`, and validate the workspace with fmt, clippy, tests, and the CLI smoke test.

## Decision 004: Stage 1 parser and ranking scope

Date: 2026-07-06
Status: accepted
Decision: Use a local dynamic-programming pinyin parser and frequency-first ranking over the embedded sample lexicon for stage 01.
Reason: Stage 01 needs a deterministic, local-only engine path that can prove `nihao`, `zhongguo`, and continuous pinyin candidates before user learning, prediction, or FFI are introduced.
Consequences: Stage 02 can add user lexicon and context scoring without changing the platform-facing session contract.

## Decision 005: User lexicon SQLite schema

Date: 2026-07-06
Status: accepted
Decision: Store user-learned phrases in SQLite table `user_phrases(phrase, pinyin, compact_pinyin, frequency, updated_at_ms)` with primary key `(phrase, pinyin)`.
Reason: Stage 02 needs durable local learning while avoiding full sentence storage and keeping lookup deterministic for tests.
Consequences: User learning writes only selected phrase and pinyin frequency data; strict privacy mode and disabled learning skip these writes.

## Decision 006: FFI memory ownership

Date: 2026-07-06
Status: accepted
Decision: Expose the C ABI from a dedicated `ffi/ime_ffi` crate and make every `ImeOutput*` own its candidate array and UTF-8 strings until `ime_output_free` is called.
Reason: Keeping unsafe C boundary code outside `ime_core` preserves the safe Rust core while giving platform hosts a stable ownership model.
Consequences: Platform hosts must free each non-null output exactly once, must not cache output-owned pointers after free, and receive null pointers instead of Rust panics crossing the FFI boundary.

## Decision 007: Windows TSF host architecture

Date: 2026-07-06
Status: accepted
Decision: Implement the Windows host as a thin C++ 20 TSF in-process DLL that maps TSF key events into the shared C ABI and keeps pinyin parsing, ranking, learning, and prediction in Rust.
Reason: The platform host should own only COM/TSF integration, composition updates, candidate UI, and text commits while preserving one cross-platform engine implementation.
Consequences: Windows-specific code lives under `platform/windows_tsf`; production readiness still requires Windows signing, installer packaging, high-DPI candidate UI polish, and Windows 11 smoke validation.

## Decision 008: macOS IMK host architecture

Date: 2026-07-06
Status: accepted
Decision: Implement the macOS host as a thin Swift InputMethodKit app bundle that maps IMK events into the shared C ABI and builds through a lightweight shell script rather than a generated Xcode project.
Reason: Stage 05 needs an auditable, local POC that can create an installable `.app` input method bundle while preserving one Rust engine implementation.
Consequences: macOS-specific code lives under `platform/macos_imk`; release readiness still requires Developer ID signing, notarization, packaged install/uninstall, icon assets, settings UI, and manual app compatibility validation.

## Decision 009: Settings and installer stage scope

Date: 2026-07-06
Status: accepted
Decision: Load desktop settings through JSON snapshots passed into the C ABI, keep settings and user lexicon data in platform application-data directories, and deliver Stage 6 installers as unsigned prototype packages.
Reason: The shared Rust engine should own settings validation, strict privacy behavior, and user lexicon clear/export semantics while platform hosts stay thin. Stage 6 also needs repeatable installer artifacts without blocking on release signing infrastructure.
Consequences: Windows and macOS hosts create or pass platform-local `settings.json` paths at engine startup; settings changes require an engine/session reload to take effect. Release readiness still requires signed Windows and macOS installers, notarization on macOS, and automatic-update planning.

## Decision 010: iOS keyboard architecture

Date: 2026-07-06
Status: accepted
Decision: Implement iOS as a Swift container app plus `UIInputViewController` keyboard extension that links the existing Rust C ABI as a static library.
Reason: iOS custom keyboards must be packaged as an app extension, while the shared Rust core should continue to own pinyin parsing, ranking, prediction, and privacy-sensitive learning behavior.
Consequences: iOS-specific code lives under `platform/ios_keyboard`; `RequestsOpenAccess` stays false by default, the keyboard includes a Globe key, and release readiness still requires App Store signing, App Group design, and simulator/device smoke testing.
