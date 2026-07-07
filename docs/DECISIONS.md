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

## Decision 011: Stage 8 validation split

Date: 2026-07-06
Status: accepted
Decision: Treat Stage 8 as validation and CI hardening: automate Rust/shared-code checks on Ubuntu and Windows plus Windows TSF compilation in GitHub Actions, while recording Windows/macOS/iOS runtime IME behavior through manual platform smoke-test records.
Reason: CI can reliably catch Rust, C ABI, source scaffold, and Windows C++ compile regressions, but TSF activation, IMK candidate routing, iOS keyboard enablement, password-field fallback, and prediction retention after UIKit callbacks require real platform hosts.
Consequences: `OI-022` can close once the Windows compile job lands and passes; runtime smoke items such as `OI-018`, `OI-029`, `OI-031`, and `OI-038` remain open until evidence is recorded from the target systems.

## Decision 012: Stage 9 core hardening boundary

Date: 2026-07-06
Status: accepted
Decision: Harden the shared Rust engine by adding indexed compact-pinyin lookup, SQLite range-prefix lookup, exact-before-prefix ranking tiers, candidate paging, top-candidate punctuation commits, and sanitized error-code logging, while keeping production lexicon replacement gated on an explicit data-license decision.
Reason: Platform hosts should consume a stable paged candidate surface from the C ABI while the Rust core owns lookup, ranking, privacy, and learning semantics. The project cannot import third-party dictionary data safely until source, license, version, and transformation steps are documented.
Consequences: Core open items for indexing, paging, punctuation, range queries, exact preservation, ranking fusion, and sanitized user-lexicon error logs can close. `OI-001` remains open until the owner selects and approves a compatible production lexicon source.

## Decision 013: Stage 10 platform polish boundary

Date: 2026-07-06
Status: accepted
Decision: Polish the existing thin platform hosts without expanding the C ABI: Windows TSF improves candidate popup anchoring, DPI/dark-mode rendering, and window-class lifecycle; macOS IMK adds a lightweight preferences window for common settings.
Reason: Stage 10 should reduce real-application rough edges while preserving the shared Rust engine contract and avoiding high-risk TSF display-attribute provider work until it can be validated on Windows.
Consequences: Windows candidate-positioning and popup lifecycle open items can close once Windows CI compiles. Full TSF display attributes, custom macOS menu icon assets, and app-by-app runtime smoke validation remain tracked separately.

## Decision 014: Stage 11 settings and iOS privacy boundary

Date: 2026-07-07
Status: accepted
Decision: Use `config/default_settings.json` as the packaged default template for platform hosts, keep CapsLock hidden from settings UI until host semantics are implemented, and make iOS learning an explicit opt-in backed by App Group storage while `RequestsOpenAccess` remains false.
Reason: Settings drift and implicit iOS persistence are both privacy and support risks. Stage 11 should close those gaps without changing the C ABI shape or pretending release provisioning has been completed.
Consequences: Desktop and iOS hosts patch only platform-local paths into the shared template, iOS can pass a real settings path to the Rust engine, and remaining iOS validation stays tracked as manual smoke/provisioning work.

## Decision 015: Stage 12 release packaging boundary

Date: 2026-07-07
Status: accepted
Decision: Prepare release-candidate packaging through configurable signing, notarization, provisioning, and App Store export hooks, while keeping final license, production lexicon approval, owner credentials, and platform smoke-test evidence as explicit release gates.
Reason: Release automation should be auditable before credentials are available, but the project must not claim public release readiness without signed artifacts, notarization results, App Store provisioning, and license/data decisions.
Consequences: Windows and macOS package scripts can build local unsigned artifacts by default and require explicit signing flags for release candidates. iOS App Store packaging requires owner-provided team and export options. The initial public release plan uses platform-native distribution channels and defers in-app auto-update frameworks.

## Decision 016: Stage 13 lexicon import boundary

Date: 2026-07-07
Status: accepted
Decision: Replace the eight-word embedded development sample with first-party starter lexicon assets and add a local lexicon import/manifest tool, while keeping third-party production data behind explicit owner approval.
Reason: Local installed builds need enough first-party vocabulary to validate real typing paths, but public release data still has independent copyright and license obligations. Common upstream candidates have obligations such as LGPL/GPL or Creative Commons attribution/share-alike, so copying them into this all-rights-reserved repository without an owner license decision would create release risk.
Consequences: The Rust core now embeds active `base_lexicon.tsv` and `bigram.tsv` starter assets. `tools/lexicon_builder` can convert local project TSV or CC-CEDICT-style files into the project format and write an audit manifest, but generated production data is not release-ready unless the manifest is explicitly marked approved after owner review. `OI-001` remains open.

## Decision 017: macOS input source default state

Date: 2026-07-07
Status: accepted
Decision: Keep the macOS input mode `tsInputModeDefaultStateKey` set to `false`.
Reason: Local System Settings debugging showed that marking a third-party input mode default-enabled can make it disappear from the add-input-source selector even when the bundle is installed and localized correctly. The actual `.pkg` install path must be smoke-tested by finding `PrivatePinyin 拼音` under Simplified Chinese and typing `nihao -> 你好`.
Consequences: Future TIS metadata edits must preserve this value unless a replacement registration strategy is validated through the real package install path, not only a temporary per-user test bundle.
