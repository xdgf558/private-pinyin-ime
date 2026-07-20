# Development Progress

Last updated: 2026-07-20 23:24
Current stage: macOS imported-lexicon status hardening
Current status: the imported-source status is no longer vertically clipped, new rime-ice/雾凇 local imports receive a stable 雾凇拼音 label, and legacy layers explicitly request re-import because normalized rows retain no source path

## macOS Imported Source Status Validation (2026-07-20)

- The imported-source label is a single-line, vertically resistant AppKit field with a full-text tooltip, preventing compact Station Board scaling from clipping glyphs.
- macOS menu and preferences imports share one source resolver. Known upstream files under `rime-ice`, `雾凇`, or `霧凇` record `雾凇拼音`; custom files keep their cleaned filename, and only dates at or below the matched source directory are retained as metadata-only versions.
- Existing `imported_lexicon.tsv` layers without `imported_lexicon_manifest.json` remain usable but are labelled as legacy. The app does not invent provenance from normalized phrase/pinyin rows or retain the user's original path.
- `scripts/test_macos_imported_lexicon_source.sh`, local-import and macOS source checks, the complete macOS IMK build, `cargo fmt --all -- --check`, `cargo test --workspace`, and strict workspace Clippy: passed.

## macOS Shared Engine Memory Validation (2026-07-20)

- Activity Monitor investigation found 17 input controllers and 18 independently parsed engines in one long-running process; heap growth matched roughly one full lexicon/index allocation per engine rather than the tiny AI Lite coefficient package.
- The macOS C ABI bridge now owns only a per-controller session. A locked process-wide pool owns the engine, serializes engine-level administration, and coalesces settings/imported-lexicon reload fan-out by exact settings data plus imported-file metadata.
- Existing sessions remain valid while a changed shared snapshot is replaced because Rust sessions retain their own `Arc` references; every controller still has isolated raw input, candidate page, context, and secure-input state.
- Replacement is constructed before the previous engine is released, deliberately accepting a short two-snapshot memory peak so a failed rebuild can preserve working input. Each failed configuration fingerprint emits one content-free Unified Logging error code and is not retried until its fingerprint changes.
- `scripts/test_macos_shared_engine.sh` creates 24 bridges, asserts a single engine load, verifies two simultaneous compositions remain independent, reloads every bridge, and asserts unchanged configuration does not reparse the lexicon.
- The native 24-session regression peaked at `53,280,768` bytes RSS (about 50.8 MiB) on the development Mac, compared with the diagnosed long-running process where 18 independent engine snapshots had grown to about 2.07 GB of Rust heap; this is local reference evidence, not a portable CI threshold.
- Real installed-app Activity Monitor validation with 5 and 20 client apps remains required before closing the memory portion of OI-042.

## Imported Lexicon Visibility Validation (2026-07-20)

- macOS and iOS display imported-source metadata from a separate atomic JSON manifest; clearing the imported layer also clears its source record.
- The optional iOS `rime-ice` import is container-App-only, requires an explicit confirmation, uses an ephemeral session, and pins release, final HTTPS host, exact byte count, and SHA-256 for every reviewed file.
- Partial reviewed-source imports are labelled as partial and are replaced by the complete status after a successful retry.
- The official `cn_dicts.zip` release asset and all three fixed raw tag URLs were independently downloaded on 2026-07-20; exact byte counts and SHA-256 values match, and the evidence/tooling is recorded in `docs/local_rime_lexicon_import.md`.
- Decision 037 remains the merged AI-08 policy; the optional verified upstream lexicon import is Decision 038 and explicitly directs GitHub-restricted networks to the local document-picker path instead of an unofficial mirror.
- Local document-picker parsing/import now runs on a user-initiated worker queue while security-scoped access remains active; only progress and completion state return to the main thread.
- `cargo test --workspace`, `cargo test -p private_pinyin_ime_ffi --features ios-ai`, `cargo test -p private_pinyin_ime_ffi --features desktop-ai`, `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, macOS source/build checks, AI-07/AI-08 source checks, iOS source checks, and local-import source checks: passed.
- Xcode 27.0 Beta (`27A5194q`) simulator-target build: `BUILD SUCCEEDED` for the container App and Keyboard Extension.
- Real-device download/import remains a release smoke item because this branch deliberately does not automate a network action on the owner's phone.

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
| 12 | Release packaging and distribution | completed | 2026-07-07 08:35 | Release distribution plan, Windows signing hooks, macOS Developer ID/notarization hooks, iOS App Store archive/export templates, automatic update strategy, and Stage 12 checks are ready for local review |
| 13 | Lexicon import and production dictionary | completed | 2026-07-08 10:42 | Merged to `main` through PR #10 |
| 14 | iOS signing and App Group configuration | completed | 2026-07-09 11:20 | Merged to local `main`; owner signing env inputs, bundle ID overrides, App Group build-setting injection, export-options checks, and Stage 14 CI source gates are ready |
| 15 | iOS simulator/local development build | completed | 2026-07-10 13:32 | Beta Xcode source/readiness gates and iOS 27 Simulator install, enablement, continuous-pinyin, prediction, local learning, portrait, and landscape smoke checks passed |
| 16 | TestFlight archive and upload | completed | 2026-07-19 20:44 | TestFlight candidate `0.1.23 (19)` was archived with Xcode 26.6, uploaded as delivery `586c1d52-6389-4564-a097-db40555f32ad`, and validated as App Store eligible |
| 17 | Device keyboard behavior and privacy closure | in_progress | 2026-07-19 17:05 | The current review branch fixes the five-candidate fallback that hid `猫` for `626`, adds explicit nine-key candidate paging, implements the requested five-column layout, and improves candidate panning, haptics, and the `A`/`L` edge hit regions; final TestFlight host taps, password/phone fallback, and App Group checks remain |
| 18 | App Store release preparation | planned | | Prepare screenshots, description, privacy labels, age rating, URLs, and release checklist |

## Core Follow-up Status

| Item | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| OI-045 | Incremental lattice caching and mixed full-pinyin/initial decoding | completed | 2026-07-16 11:28 | Session-local append/backspace prefix reuse, context/boundary invalidation, joint full/initial beam edges, `wojt -> 我今天`, raw-English fallback protection, C ABI coverage, and latency regression checks are ready for review |

## iOS Regression Validation (2026-07-18)

- `cargo test --workspace`, `cargo fmt --all -- --check`, and `cargo clippy --workspace --all-targets -- -D warnings`: passed.
- Focused nine-key tests cover `64426 -> 你好`, continuous digit segmentation, Backspace/commit behavior, and the interactive lookup budget: passed.
- `scripts/check_ios_keyboard_sources.sh`: passed with contracts for extension-local preference fallback, delayed self-change callback handling, revised nine-key geometry, and symbol entry.
- Xcode 27.0 (`27A5194q`) simulator build: `BUILD SUCCEEDED`; the app installed and launched on an iOS 27.0 iPhone 17 Pro simulator.
- Wrote `nine_key` and `traditional` to the extension-local preference domain, fully restarted the simulator, and read both back unchanged: passed.
- Production-lexicon regression ranks `zyao` as `主要 (zhu yao)` first: passed.
- Mixed shorthand decoding is capped at 16 characters, avoids sort-comparator allocations, and keeps the 16-character regression below the shared 60-ms input budget: passed.
- Common full-pinyin regressions keep `woshi -> 我是`, `jintian -> 今天`, and `zhongguo -> 中国` first after mixed/continuous candidates enter one score-sorted bucket: passed.
- Delayed self-generated text callbacks now require a matching document identifier and captured text context inside a 250-ms window; unrelated field/app changes continue to reset composition.
- Layout/script reads compare shared-JSON and extension-local timestamps, so the freshest successful write wins while either sandbox remains a usable fallback.
- `scripts/run_ios_smoke_readiness.sh`: passed with `BUILD SUCCEEDED` for both the container app and Keyboard Extension under Xcode 27.
- Final TestFlight/device taps for candidate selection, top-left symbol navigation, revised geometry, and delayed host callbacks remain required before release.

## iOS Nine-Key Candidate and Touch Validation (2026-07-19)

- Added a bounded session-level candidate-page setter to the Rust core and C ABI; iOS requests exactly nine entries even when engine construction falls back to default settings.
- Added executable C ABI coverage proving nine-key `626` returns nine visible candidates, includes `猫` on the first page, and produces a distinct non-empty second page: passed.
- Added a dedicated `候选` key for the next candidate group; the fixed previous/next controls above the horizontally scrolling strip remain available.
- Rebuilt the nine-key surface into the requested five-column geometry, restored the required Globe and Chinese/English controls, removed the placeholder key, and made row heights adapt to compact-height layouts.
- Candidate-page configuration now has one bridge-owned preferred size and degrades to the core default without making the keyboard unavailable; haptics remain best-effort because the extension does not request Full Access.
- Added cancellable candidate-button tracking, preserved scroll position, and expanded non-overlapping `A`/`L` edge hit regions.
- `cargo test --workspace`, `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `scripts/check_ios_keyboard_sources.sh`: passed.
- Xcode Beta simulator build: `BUILD SUCCEEDED`; the app installed and launched on an iOS 27.0 iPhone 17 Pro simulator.
- TestFlight device validation is still required for candidate-strip inertial dragging, `A` accuracy, optional haptic behavior, five-column portrait/landscape geometry, required Globe access, Chinese/English switching, `626 -> 猫`, and repeated `候选` paging before release.

## Local AI Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| AI-01 | Offline evaluation baseline | completed | 2026-07-14 14:34 | 13/13 required regressions pass; 7 correction/mixed-input opportunities are measured; latency remains report-only |
| AI-02 | Runtime contracts and mock provider | completed | 2026-07-16 06:40 | Isolated zero-dependency contracts, bounded budgets/deadlines, full request identity, scoped cancellation, redacted debug output, deterministic mock behavior, non-cryptographic fingerprint limits, worker-queue-only host guidance, and CI source checks are ready for review |
| AI-03 | Privacy guard and source gates | completed | 2026-07-16 10:04 | Merged to `main` through PR #25; guarded construction, secure/sensitive/oversized rejection, eight-token context minimization, code-only errors, and no-network/no-content-log source gates remain isolated from production input |
| AI-04 | Rules-first correction, terms, and cleanup suggestions | completed | 2026-07-17 10:05 | Two-result validated pinyin correction, first-party canonical English terms, strict-privacy-blocked read-only cleanup analysis, redacted debug output, and 13/13 required plus 7/7 observed offline quality are ready for review; hosts remain untouched |
| AI-05 | Model manifest, approval, integrity, and hardware gate | completed | 2026-07-17 15:09 | Merged to `main` through PR #29; strict schema, dual-control Owner approval, bounded integrity/use-time verification, safe paths, local-only privacy, platform/hardware gates, atomic packager, and CI checks form the model supply-chain boundary |
| AI-06 | Shared compact Rust AI Lite ranker | completed | 2026-07-18 00:15 | Fixed-point stable ranking over six bounded engine signals, ranker/feature schema version gates, exact AI-05-approved 426-byte first-party coefficients, overflow boundaries, 8/8 targeted improvements, 4/4 preservation cases, bounded cancellation/scratch state, and no host integration are ready for review |
| AI-07 | macOS and Windows asynchronous integration | completed | 2026-07-19 06:36 | Merged to `main` through PR #33; bounded asynchronous desktop ranking, stale-result rejection, secure-input cancellation, macOS IMK wiring, Windows TSF wiring, and the signed/notarized macOS 0.1.22 validation package are complete |
| AI-08 | iOS AI Lite integration | completed | 2026-07-20 | Merged to `main` through PR #36; isolated `ios-ai` feature, approved 426-byte local ranker, bounded non-blocking worker, stale-result rejection, secure-input fallback, controller-lifetime memory-pressure suspension, and iOS 27 simulator build are complete; real-device latency/RSS and hardware calibration remain release gates |
| AI-09 | Authenticated desktop Helper boundary | completed | 2026-07-20 15:46 | Shared bounded protocol and helper, controlled macOS pipes, current-user-only Windows request/response named-pipe pair, per-launch authentication, health/cancel/crash/restart/shutdown/idle lifecycle, packaging/signing hooks, and CI probes are ready for review; no Writer model or input-path dependency is added |
| AI-10 to AI-12 | Optional Writer feasibility and cross-platform hardening | planned | | Follow `docs/local_ai_development_plan.md` one reviewed PR at a time; every artifact must pass AI-05 |

## AI-09 Validation

- Shared protocol tests cover deterministic framing, 64-KiB fail-before-allocation limits, redacted diagnostics, constant-time fail-closed authentication, bounded payload decoding, and the ten-minute maximum idle policy.
- Helper process tests cover authentication, health, bounded mock work, completed-worker handle reclamation, cancellation, graceful shutdown, unauthenticated rejection, and idle process exit without logging request payloads.
- macOS builds the helper in release mode and separately signs `Contents/Helpers/PrivatePinyinAIHelper`; the Swift controlled-child test exercises authentication, health, cancellation, forced termination, automatic restart, and clean shutdown over anonymous pipes.
- Windows builds and packages `PrivatePinyinAIHelper.exe`; its lifecycle probe uses a random current-user-only request/response named-pipe pair with `PIPE_REJECT_REMOTE_CLIENTS`, verifies both connected clients match the spawned helper PID, terminates one authenticated helper, relaunches another, then exercises cancellation and shutdown.
- CI now runs the shared source/privacy gate on Ubuntu, the compiled controlled-process test on macOS, and the compiled named-pipe lifecycle probe on `windows-2022`.
- AI-09 is infrastructure only. Basic pinyin, user learning, AI Lite ranking, and iOS do not invoke the helper. `AI-OI-010` tracks real signed-package identity, hang/timeout fault injection, and ten-minute idle smoke before Writer features are enabled.

## AI-08 Validation

- `cargo test -p private_pinyin_ime_ffi --features ios-ai`: passed, including iOS platform enablement, secure-input base fallback, unsupported-memory rejection, invalid-platform rejection, and ordinary input after every rejected AI path.
- `cargo test -p private_pinyin_ime_ffi --features desktop-ai`: passed, confirming the generic local-AI ABI preserves AI-07 desktop behavior.
- `cargo clippy -p private_pinyin_ime_ffi --all-targets --features ios-ai -- -D warnings`, `cargo fmt --all`, `check_ai08_ios_integration_sources.sh`, `check_ai07_desktop_integration_sources.sh`, and `check_ios_keyboard_sources.sh`: passed.
- Xcode Beta iOS 27 simulator build through `scripts/build_ios_keyboard.sh`: `BUILD SUCCEEDED` with Rust `aarch64-apple-ios-sim`, the C support module, container App, and Keyboard Extension.
- The iOS build enables only `ios-ai`, keeps `RequestsOpenAccess=false`, embeds no heavy neural model, and contains no keyboard-extension network API or URL.
- `didReceiveMemoryWarning` now cancels optional AI through the secure-input path and keeps it suspended for the controller lifetime while preserving the current composition and ordinary input path.
- Real-device iOS measurements remain required for first-enable latency, extension resident memory, available-memory rejection/recovery, secure-field system fallback, numeric/phone fail-closed behavior, queue saturation, and unchanged base typing before release approval or hardware-policy changes. The matrix must include at least one 8-GiB device that exercises the enabled path and one sub-8-GiB device that verifies fallback.

## AI-07 Validation

- `cargo fmt --all`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo clippy -p private_pinyin_ime_ffi --all-targets --features desktop-ai -- -D warnings`: passed.
- `cargo test --workspace`: passed, including 53 local-AI core tests and the new exact-permutation candidate-page mutation guard.
- `cargo test -p private_pinyin_ime_ffi --features desktop-ai`: passed with worker-backed desktop C ABI coverage, secure-input fallback, stable partial-order completion, mismatch rejection, and an executable expired-ready-result no-reorder regression.
- `bash scripts/check_ai03_privacy_sources.sh`, `check_ai05_model_gate_sources.sh`, `check_ai06_lite_ranker_sources.sh`, and `check_ai07_desktop_integration_sources.sh`: passed; no network/external AI runtime or content log was introduced.
- `bash scripts/run_c_demo.sh`, `check_macos_imk_sources.sh`, and `check_windows_tsf_sources.sh`: passed.
- `bash scripts/build_macos_imk.sh`: passed with the `desktop-ai` FFI feature and produced `dist/macos_imk/PrivatePinyin.app`.
- GitHub Actions run `29653165683` passed Rust, macOS lifecycle, and Windows `windows-2022` MSVC/TSF jobs after the AI-07 merge.
- Physical MacBook Air M5 validation passed bounded queue pressure, expired/mismatched/invalid-order rejection, secure-input cancellation and base fallback, and exact 4096/8191/8192/16384-MiB hardware-threshold checks.
- Real secure-input probes observed the platform signal in a native `NSSecureTextField`, Chrome password field, and Safari password field; the signal returned to normal after the test fields closed.
- Windows 11 TSF password-field behavior and queue-pressure smoke still require a real Windows host; they cannot be closed by the macOS build or CI compiler alone.
- iOS build scripts do not enable `desktop-ai`; AI-08 uses the isolated `ios-ai` feature and the same bounded local worker without desktop host code.

## AI-06 Validation

- `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- `bash scripts/check_ai05_model_gate_sources.sh`: validates the approved package, exact files, hashes, sizes, external fingerprint, license, privacy, platform, and hardware declarations.
- `bash scripts/check_ai06_lite_ranker_sources.sh`: validates bounded source contracts and requires eight targeted improvements with zero preservation regressions.
- `.gitattributes` pins hashed model JSON and notice files to LF so Windows checkout cannot alter approved artifact bytes.
- Offline quality: baseline Top-1 `4/12`, MRR `0.653`; AI Lite Top-1 `12/12`, MRR `1.000`; 8 improved, 0 regressed, 0 gate failures.
- Local arm64 macOS reference inference: maximum `5 us`, mean `2.1 us` across the 12-case dataset; CI uses the deterministic 30 ms contract test rather than portable latency claims.
- Artifact: model version `1.0.1`, ranker `ai06-v1`, feature schema `1`, SHA-256 `340a2e54f2f5aace39728b38e968a1e4fee8740aab7c41c20af00923e8b85dbd`, 426 bytes; approval fingerprint `8bc7977a88f64a818fd232b7cfafd19af477232259e700d690ea37dfa639d439`.
- Boundary regressions cover maximum approved features, weights, candidate count, `i64` base-score extremes, and a `usize::MAX` rank-normalization input without arithmetic overflow.
- `AI-OI-009` tracks broader owner-approved typo, mixed-English, and long-candidate benchmarks before AI-07 without collecting production typing data.
- Production behavior: unchanged. No FFI, macOS, Windows, iOS, settings, or input-thread path invokes the ranker before AI-07.

## Update Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| UPDATE-01 | macOS version check and reminder | completed | 2026-07-14 22:27 | Merged to `main` through PR #20; fixed HTTPS feed, opt-in checks, strict-privacy gate, manifest validation, and update UI are complete |
| UPDATE-02 | Verified package download and Installer handoff | completed | 2026-07-15 00:08 | Bounded private download, SHA-256/size/signature/notarization verification, two-step consent, and visible system Installer handoff are ready for review |
| UPDATE-03 | Post-install process refresh | completed | 2026-07-15 10:38 | Merged to `main` through PR #22; dedicated UI-only postinstall helper, same-bundle launch-time detection, consent/revalidation, normal exit, success guidance, and logout-only fallback are complete |

## UPDATE-03 Validation

- `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- `bash scripts/run_c_demo.sh` and `bash scripts/build_macos_imk.sh`: passed.
- UPDATE-01, UPDATE-02, UPDATE-03, AI-01, macOS IMK, installer/settings, Stage 11, Stage 12, Stage 15, and Stage 16 source gates: passed.
- AppKit visual smoke: stale-process initial state and successful-refresh state rendered without clipping; both UI-only test instances exited after their final windows closed.
- Temporary unsigned pkg smoke: `pkgbuild` included the UPDATE-03 `postinstall`; the expanded script passed `sh -n` and launched the fixed signed-bundle executable path rather than unsupported LaunchServices `open`. The temporary package was removed after inspection.

## OI-045 Validation

- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- `bash scripts/run_c_demo.sh` and `bash scripts/build_macos_imk.sh`: passed; the public C ABI is unchanged.
- Stage 09 core, Windows TSF, macOS IMK, iOS keyboard, platform-validation, and AI-01 evaluation source gates: passed.
- Production lexicon behavior: `wojt` ranks `我今天` first; backspace plus retyping preserves the same visible ranking; `abc` still has no candidate and commits raw input.
- Cache behavior: append reused two then three normalized prefix characters, backspace reused the retained prefix, and changed apostrophe boundaries or previous context invalidated the affected cached suffix.
- Report-only arm64 macOS release benchmark: engine initialization p50 `36.84 ms` / p95 `61.13 ms`, continuous pinyin p95 `3.33 ms`, and mixed full/initial p95 `0.26 ms`; these are local reference values, not portable CI thresholds, and `OI-042` remains the cross-platform initialization follow-up.
- AI-01 required regressions remain `13/13`; the pre-existing observation case `mixed_full_initials` now meets target `1/1` through deterministic core behavior without any AI provider or model.

## iOS Keyboard UI Follow-up Validation

- Added a persistent inline `简体` / `繁體` output selector. Candidate display, predictions, and commits use the local system Chinese transform while core candidate identity and learning remain shared and normalized.
- Changed nine-key composition display to use the leading candidate's readable pinyin when available, so valid signatures such as `9664` no longer expose internal lookup digits; renamed the generic Return action from `换行` to `回车`.
- Beta Xcode readiness build: passed with `BUILD SUCCEEDED` for both the container app and Keyboard Extension; the resulting Debug app installed and launched on the iPhone 17 Pro / iOS 27 Simulator.
- Local conversion regression: `里面头发发展干嘛面条` produced `裡面頭髮發展乾嘛麵條`; 50,000 short-string conversions completed in approximately 0.03 seconds on the local Mac reference machine.
- iOS 27 runtime phrase probe confirmed that the system transform is phrase-aware for `头发 -> 頭髮`, `面条 -> 麵條`, `皇后在后面 -> 皇后在後面`, and `只有一只猫 -> 只有一隻貓`; a compiled regression now runs in the macOS CI job. The option remains documented as generic Traditional rather than complete Taiwan/Hong Kong localization.
- Simulator settings regression: a fresh local settings repair persisted `ios_chinese_script = simplified`, preserving the existing default until the user explicitly selects `繁體`.
- Expanded the iOS runtime candidate page from five to nine entries; long candidates remain readable in a horizontally scrollable strip, while group navigation stays fixed outside the scroll content.
- Added a dedicated `#+=` iOS symbol page covering the requested bracket, operator, book-title, punctuation, ellipsis, and separator characters without replacing the existing numeric/basic-symbol page.
- `bash scripts/check_ios_keyboard_sources.sh` and `bash scripts/run_ios_smoke_readiness.sh`: passed with Xcode 27 and the iOS 27 Simulator build.
- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed after the shared OI-045 decoder was included.
- iPhone 17 Pro / iOS 27 Simulator visual smoke: Station Cat colors, compact candidate strip, balanced QWERTY, adaptive nine-key controls, Shift/delete symbols, and inline preferences rendered without clipping.
- Full-key behavior: `nh` ranked `你好` first; an `a` candidate page moved forward and backward with fixed visible controls; touch-down typing produced one event per tap.
- Nine-key behavior: the saved layout reopened correctly, `64426` ranked `你好` first, and one candidate tap inserted exactly one `你好` into Messages.
- The system-owned bottom dictation key remains available when iOS provides it; the extension does not show a duplicate non-functional microphone control.

## iOS 0.1.20 (16) TestFlight Upload

- `plutil -lint`, `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`: passed.
- `bash scripts/run_ios_smoke_readiness.sh` with Xcode 26.6 (`17F109`) and iPhoneOS 26.5: passed with `BUILD SUCCEEDED`.
- The device Rust static library was rebuilt with `IPHONEOS_DEPLOYMENT_TARGET=18.0`; `vtool` reports the bundled SQLite object as iOS `minos 18.0` / SDK 26.5.
- Signed archive `dist/ios/PrivatePinyin-0.1.20-build16-xcode26.xcarchive` reports version `0.1.20`, build `16`, and arm64.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `9824d39f-ef1a-4fe2-a024-ad0bfd86b0be`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, and `IS-ON-APP-STORE-CONNECT: true`.
- External TestFlight review: submitted; `BUILD-STATUS` and `BETA-REVIEW-STATE` are both `WAITING_FOR_REVIEW`.

## iOS 0.1.21 (17) TestFlight Upload

- Container app and Keyboard Extension versions were advanced together to `0.1.21 (17)` in release commit `ab1fd88`.
- The device Rust FFI library was rebuilt for `aarch64-apple-ios` with `IPHONEOS_DEPLOYMENT_TARGET=18.0`.
- Signed archive `dist/ios/PrivatePinyin-0.1.21-build17-xcode26.xcarchive` reports version `0.1.21`, build `17`, and arm64.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `cd60fb42-9506-4aee-a7e8-4d71bb9d55cb`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, `BUILD-STATUS: BETA_INTERNAL_TESTING`, and `IS-ON-APP-STORE-CONNECT: true`.
- External TestFlight review: ready for the Owner to finish the test-content form, assign build `17` to the external group, and submit it for Beta App Review.

## iOS 0.1.22 (18) TestFlight Upload

- PR #32 was approved and merged to `main` as `3e33c42`; container app and Keyboard Extension versions were advanced together in release commit `4c1cae9`.
- The device Rust FFI library was rebuilt for `aarch64-apple-ios` with `IPHONEOS_DEPLOYMENT_TARGET=18.0`.
- Signed archive `dist/ios/PrivatePinyin-0.1.22-build18-xcode26.xcarchive` reports version `0.1.22`, build `18`, and arm64.
- `plutil -lint` for both release plists and `bash scripts/check_ios_keyboard_sources.sh`: passed.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `fe40dc42-10f0-4c4c-abd5-5bd9da81e122`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, `BUILD-STATUS: BETA_INTERNAL_TESTING`, and `IS-ON-APP-STORE-CONNECT: true`.
- External TestFlight review: ready for the Owner to add build `18` to the external group, provide test content, and submit it for Beta App Review.

## iOS 0.1.23 (19) TestFlight Upload

- PR #35 was merged as `b44eb7f` and PR #34 was merged as `a915ec6`; container app and Keyboard Extension versions were advanced together in release commit `c56a9a3`.
- `cargo fmt --all -- --check`, `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`, both release-plist lints, the iOS source gate, and the local Rime import source gate passed.
- The device Rust FFI library was rebuilt for `aarch64-apple-ios` with `IPHONEOS_DEPLOYMENT_TARGET=18.0`.
- Signed archive `dist/ios/PrivatePinyin-0.1.23-build19-xcode26.xcarchive` reports version `0.1.23`, build `19`, and arm64.
- `xcodebuild -exportArchive` with `destination=upload`: passed; App Store Connect accepted delivery `586c1d52-6389-4564-a097-db40555f32ad`.
- Apple processing: passed; `IMPORT-STATUS: VALID`, `BUILD-AUDIENCE-TYPE: APP_STORE_ELIGIBLE`, `BUILD-STATUS: BETA_INTERNAL_TESTING`, and `IS-ON-APP-STORE-CONNECT: true`.
- External TestFlight review remains a separate Owner action: assign build `19` to the external group, provide test content, and submit it for Beta App Review.

## Completed Work

- Rebuilt the iOS Keyboard Extension visual surface from the Station Cat handoff with exact warm-dark tokens, 46-point candidate strip, gradient key styles, native pressed feedback, and compact inline preferences.
- Kept QWERTY as the default while preserving the optional nine-key layout; when iOS supplies the bottom Globe key, the nine-key grid uses its left control position for a visible `全键` return action.
- Added fixed previous/next candidate-group controls around the horizontal candidate scroller and a conservative end-of-pages state so paging remains reachable with long candidate text.
- Changed typing keys to touch-down delivery without changing command-key release semantics, and made core creation retryable so a transient settings/App Group failure does not leave the keyboard inert.
- Closed `OI-045` with a session-local continuous-decoder cache that retains bounded lattice states across ordinary key appends and safely truncates them for backspace.
- Added context and apostrophe-boundary compatibility checks plus composition-lifecycle clearing so cached path scores never cross commits, cancellations, resets, mode changes, sessions, or processes.
- Unified exact full-pinyin and initial edges inside the shared beam decoder with an abbreviation penalty and a minimum full-pinyin guard; `wojt` produces `我今天` while ordinary `abc` retains raw fallback behavior.
- Added production, backspace, cache-reuse, latency, and C ABI regressions, so macOS, Windows, and iOS inherit the feature without host-specific logic or ABI changes.
- Made `AiRequestBuilder` plus `PrivacyGuard` the only public local-AI request construction path while keeping the crate isolated from the engine, FFI, and platform hosts.
- Added fail-closed policy checks for disabled features, strict-privacy opt-out, unapproved model licenses, unsupported hardware, expanded budgets, expired deadlines, mismatched candidate identity, secure input, and missing explicit rewrite/translation consent.
- Added bounded content checks and local sensitive-pattern rejection for password/secret assignments, labeled or standalone one-time codes, payment cards, Chinese identity numbers, and phone numbers without exposing rejected content in errors.
- Distinguished full-pinyin and nine-key raw input so digit-only OTP heuristics fail closed for undeclared numeric input without blocking a declared `64426 -> 你好` nine-key request.
- Retained only the last eight non-empty recent tokens, rejected oversized candidate pages instead of changing their lifecycle hash, and kept forbidden clipboard/document/web/email/chat/screen context structurally absent.
- Added eighteen local-AI runtime tests plus AI-03 privacy, no-content-log, and no-network/external-service source gates; no model or user-visible input behavior is connected.
- Added explicit false-positive regressions for ordinary `API key`, `token economy`, `secret garden`, and `password manager` discussion, and tracked a categorized privacy corpus plus future context/confirmation/allowlist policy in `AI-OI-006`.
- Added the isolated `ai/local_ai_core` crate without connecting it to the existing engine, C ABI, or platform hosts.
- Defined local AI features, hardware tiers, latency/output budgets, monotonic deadlines, sanitized error codes, request/response candidate contracts, and opaque session/request/composition/candidate-set identity.
- Added a deterministic zero-dependency mock provider whose cancellation is scoped to the complete request identity and whose responses preserve identity for stale-result rejection.
- Redacted content-bearing request, candidate, and response `Debug` output so routine diagnostics cannot expose raw pinyin, composition text, candidate text, or recent tokens.
- Added eight focused runtime-contract tests and an AI-02 CI source gate; user-visible input behavior remains unchanged.
- Documented that the FNV candidate fingerprint is lifecycle-only and cannot serve as a persistent/cross-process cache identity; recorded AI-07's mandatory bounded worker-queue dispatch for the synchronous provider contract.
- Made the macOS Station Board preferences window resizable with a fixed aspect ratio, a compact 86% default size, and a bounded 72%-100% whole-canvas scale.
- Kept every card, label, button, custom toggle, and pointer hit region synchronized through AppKit scroll-view magnification; local visual smoke covered default and minimum sizes plus a toggle round trip at minimum scale.
- Disabled independent trackpad pinch magnification so only proportional window resizing can change the board scale, preventing hidden-scroller clipping at compact window sizes.
- Added UPDATE-03 post-install lifecycle handling without changing the shared Rust engine or normal IMK typing path.
- Changed pkg follow-up launch to a new UI-only executable process in the console user's Aqua session with a bounded install timestamp, avoiding both old-instance activation and Input Method LaunchServices failures.
- Made onboarding, preferences preview, and post-install modes UI-only so they never create a competing `IMKServer` and exit after their last window closes.
- Added exact-bundle PID/launch-time detection, current-helper exclusion, click-time target revalidation, normal termination only, and a bounded wait with no force-kill path.
- Made the launch cutoff strictly conservative: subsecond timestamps are used when available, while same-boundary and later processes are always preserved; a dedicated macOS CI job now executes the Swift policy tests instead of relying on Ubuntu's skip path.
- Added Station-style success and recovery guidance: successful refresh requires only switching input sources, while a process that remains receives logout/login instructions and no routine restart prompt.
- Added pure Swift policy tests, UPDATE-03 source gates, privacy/update-strategy decisions, and macOS upgrade smoke coverage.
- Added UPDATE-02 package delivery to the macOS host while keeping the shared Rust engine and typing path network-free.
- Added same-host HTTPS `.pkg` downloads through an ephemeral no-cache/no-cookie session, with streaming and final-size enforcement plus a private single-package cache.
- Added streaming CryptoKit SHA-256 verification, pinned Developer ID Installer Team ID validation, and notarization assessment through exact-argument `pkgutil` and `spctl` subprocesses.
- Added cancel/retry states, strict-privacy download cancellation, sanitized errors, a second user confirmation, and mandatory re-verification immediately before opening Apple's visible Installer app.
- Explicitly excluded silent privileged installation, `sudo`, credential collection, and automatic process restart from UPDATE-02; post-install process refresh remains UPDATE-03.
- Added UPDATE-01 version discovery to the macOS host without changing the network-free Rust engine or typing path.
- Kept automatic checks off by default, limited opt-in checks to once per 24 hours, paused them under strict privacy, and exposed manual checks through the menu and preferences.
- Added a fixed-host schema-1 manifest with HTTPS, redirect, response-size, package-extension, SHA-256, package-size, version, and minimum-system validation plus offline Swift tests and a CI source gate.
- Established AI-01 before introducing any model: a 20-case first-party offline corpus separates 13 required engine regressions from 7 observed AI improvement opportunities.
- Added deterministic Top-1, target-rank, found-rate, and MRR reporting plus a release-mode initialization/lookup latency benchmark with no machine-dependent CI threshold.
- Recorded dataset provenance and an explicit no-user-data rule; the parser rejects provenance other than project regressions or first-party synthetic cases.
- Added the approved AI-01 through AI-12 implementation plan, including stable visible candidate numbering and stale asynchronous-result rejection requirements.
- Added an optional iOS nine-key layout without replacing QWERTY or the symbols page; Chinese users can persistently switch with `九宫` / `ABC`, while English mode continues to use QWERTY.
- Added shared Rust nine-key indexing and continuous digit-string decoding, C ABI key code `102`, learned-candidate lookup, old SQLite user-phrase migration, and regression coverage for `64426 -> 你好`.
- Added local trigram learning so the last two selected tokens can produce context-specific next-token predictions across macOS, Windows, and iOS through the shared Rust core.
- Added 30-day-half-life ranking decay, an eight-token in-memory context bound, and decayed-weight capacity eviction for all four local learning tables.
- Added user-learning regression tests for trigram context, inactivity decay, privacy write guards, export/clear behavior, bounded context, and low-weight eviction.
- Changed the macOS candidate panel to InputMethodKit's horizontal 9-column stepping layout, made nine candidates the macOS default, and added a targeted migration from the previous default page size of five.
- Routed native candidate selection keys through the macOS controller first, keeping digit selection on one core-owned path while retaining four-host manual verification as a release gate.
- Bumped the macOS app metadata to `0.1.16 (16)` and added horizontal-layout source gates and smoke coverage.
- Bumped the macOS app and installer to `0.1.17 (17)` and the Windows/core package to `0.1.13`, with bundled Simplified Chinese release notes for bounded local trigram learning.
- Diagnosed intermittent macOS input loss as repeated `EXC_BAD_ACCESS` crashes in InputMethodKit server deactivation while calling `isVisible` on a released candidate panel.
- Retained the server-attached `IMKCandidates` panel for the input-method process lifetime, added host palette cleanup, and bumped the signed macOS release to `0.1.15`.
- Installed `0.1.15` over the existing build and completed 20 TextEdit/Chrome focus switches with active and committed compositions; the process stayed alive and the existing 17 crash reports did not increase.
- Replaced first-pass continuous-pinyin segmentation with a joint raw-character lattice and bounded beam decoder shared by macOS, Windows, and iOS.
- Added logarithmic phrase scoring, starter/base bigram transitions, local user-bigram reranking, apostrophe-boundary enforcement, and internal segment learning for selected sentence candidates.
- Added ambiguity, learned-reranking, common-sentence, apostrophe, and under-60-ms lookup regression tests for the second-generation decoder.
- Bumped the macOS app and installer to `0.1.14`, updated its bundled release notes, and produced a signed, notarized, stapled package for the second-generation decoder.
- Updated the Stage 15 source gate to match the current `Host composition` and `App Group fallback` smoke-record labels so CI can validate the merged iOS record again.
- Redesigned the macOS preferences window as a fixed dark Station Board with a branded header, privacy card, two-column prediction/learning controls, settings-file panel, and release information.
- Added dynamic public-version display without the internal build number, plus bundled Simplified Chinese release notes for future package updates.
- Bumped the macOS app and installer package to public version `0.1.13` for the redesigned preferences release.
- Added an isolated `--show-preferences` visual-preview path and verified the complete window on macOS with no clipped or overlapping content.
- Updated the Stage 11 privacy source gate to match the current localized iOS learning copy.
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
- Added a Windows NSIS setup EXE packaging path for internal testing, including 64-bit TSF registration and a post-install setup guide.
- Fixed the Windows NSIS setup EXE to use the cat-brand installer icon instead of the default NSIS gear icon.
- Hardened the Windows NSIS setup EXE as version `0.1.11` by requesting administrator rights and making TSF profile registration clear stale records before reinstalling.
- Localized the Windows TSF display name and installer surfaces to `猫栈拼音`, bumped the Windows/core build to `0.1.12`, and added first-pass continuous-pinyin, initials shorthand, full-width punctuation, and common `lü` lexicon fixes.
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
- Implemented stage-12 release packaging and distribution preparation.
- Added `docs/release_distribution_plan.md` with public release gates for final license, production lexicon data, signing, notarization, iOS provisioning, platform smoke-test evidence, privacy posture, and version consistency.
- Extended Windows packaging with SignTool support for staged DLL/EXE artifacts and MSI output, plus a `-RequireSigning` gate for release candidates.
- Extended macOS app and pkg scripts with Developer ID app signing, hardened runtime, installer signing, notarytool submission, and stapling hooks while keeping ad-hoc/unsigned local builds available by default.
- Added an iOS App Store archive/export script that requires owner-provided team ID and export options.
- Added iOS App Store metadata and export-options templates under `platform/ios_keyboard/AppStoreMetadata`.
- Recorded the initial automatic update strategy: signed MSI/zip, signed/notarized pkg, and TestFlight/App Store updates first; defer Sparkle, MSIX, and App Installer.
- Added `scripts/check_stage12_release_sources.sh` and wired it into CI.
- Updated platform READMEs, script docs, changelog, decisions, open items, and development spec for Stage 12 release gates.
- Addressed stage-12 review feedback so Windows packaging signs staged PowerShell installer/settings scripts with Authenticode when a signing certificate is configured, and folded that requirement into `OI-015`.
- Added a macOS post-install onboarding window that opens after pkg installation and links users to Keyboard Settings.
- Updated macOS input method metadata for System Settings discovery and added smoke-test coverage for input-source discovery, enabling, and upgrade-onboarding behavior.
- Redesigned the macOS onboarding window with the Station Cat visual system: fixed dark appearance, warm lamp accent, Chinese setup copy, station-style step card, and hover-aware custom AppKit buttons.
- Addressed macOS onboarding review feedback by removing the `paddedBadge` local-variable shadowing risk and pinning the brand row width so the `setup` badge aligns to the right edge.
- Bumped the app and package version from `0.1.0` to `0.1.3` for the regenerated onboarding installer and input source discovery refresh.
- Fixed macOS input source discovery by setting `tsInputModeDefaultStateKey` to false; local System Settings debugging showed default-enabled third-party modes are filtered out of the add-input-source list.
- Implemented Stage 13 lexicon import and starter dictionary work.
- Added active `base_lexicon.tsv` and `bigram.tsv` first-party starter assets so installed local builds are no longer limited to the original eight-word sample lexicon.
- Changed the Rust core to load the active starter assets while retaining the original sample files as source fixtures.
- Added `tools/lexicon_builder`, a local Rust CLI that converts project TSV or local CC-CEDICT-style files into the standard base-lexicon TSV and emits an audit manifest with a release-approval flag.
- Updated lexicon policy, manifest, changelog, README, CI, and open items so `OI-001` remains open for owner-approved production data.
- Added `scripts/check_stage13_lexicon_sources.sh` and wired it into CI.
- Extended `tools/lexicon_builder` with mozillazg pinyin-data and AOSP PinyinIME rawdict import support, including UTF-16 rawdict decoding, marked-pinyin normalization, frequency scaling, and supplemental single-character readings.
- Replaced the first-party starter base lexicon with a 100,657-entry owner-approved AOSP PinyinIME rawdict import supplemented by pinyin-data single-character readings.
- Added `THIRD_PARTY_NOTICES.md`, updated the active lexicon manifest with exact upstream revisions and licenses, and closed `OI-001` for the current bundled base dictionary.
- Added a `ganma -> 干嘛` core candidate regression.
- Addressed macOS formal-pkg review feedback by documenting that `tsInputModeDefaultStateKey` must stay `false`, pinning that value in the macOS scaffold check, and recording the decision in `docs/DECISIONS.md`.
- Added a macOS C ABI fallback so the installed IMK host retries `ime_engine_new(nil)` if a user settings path cannot open.
- Verified the actual `PrivatePinyin-0.1.3.pkg` install path from `/Library/Input Methods`: `PrivatePinyin 拼音` appears under Simplified Chinese, the TIS mode can be enabled/selected, and TextEdit commits `nihao -> 你好`.
- Added the redesigned macOS template menu icon, color app icon, and `InfoPlist.strings` localization fallback resources.
- Wired the new icon resources into the macOS IMK plist, build script, package output, and scaffold checks.
- Bumped the workspace, platform plist, and package default versions to `0.1.7` for the icon/name refresh.
- Renamed the macOS Chinese input source display name to `猫栈拼音`, with localized input method name `猫栈`.
- Closed `OI-028` for macOS settings entry and menu icon assets; real light/dark menu-bar icon appearance still needs macOS smoke evidence.
- Localized the macOS input method menu, preferences window, and settings action alerts into Chinese.
- Updated the macOS onboarding window title, brand label, and setup subtitle to consistently refer to `猫栈拼音`.
- Bumped the workspace, platform plist, and package default versions to `0.1.8` for the macOS menu localization refresh.
- Redesigned the macOS preferences window with the Station Cat dark visual system, custom toggle controls, a settings path card, and hover-aware AppKit buttons.
- Extended macOS scaffold checks to pin the redesigned preferences window's fixed dark appearance, Chinese settings copy, custom toggles, and hover states.
- Bumped the workspace, platform plist build numbers, and package default versions to `0.1.9` for the macOS preferences UI refresh.
- Added a macOS public-release checklist for personal-website distribution, including Developer ID setup, notarization, website download copy, smoke tests, and manual update flow.
- Added `scripts/check_macos_public_release.sh` to gate public `.pkg` publication on Developer ID identities, package signature, Gatekeeper install assessment, stapled notarization, notarytool profile access, and SHA256 output.
- Documented that the local pkg remains blocked for public website distribution until Owner-provided Developer ID certificates and notarization evidence are available.
- Added first-pass local user bigram learning so selecting `A` then `B` teaches the local predictor to suggest `B` after future `A` commits.
- Kept user bigram learning behind the existing `enable_user_learning` and `strict_privacy_mode` write guards.
- Extended user lexicon clear/export behavior to cover learned one-step prediction transitions.
- Added second-pass local short phrase learning so selecting `A`, `B`, then `C` can teach the local predictor to suggest `BC` after future `A` commits.
- Kept short phrase learning bounded to two-token continuations with a 12-character phrase cap, and covered it with clear/export behavior.
- Addressed short-phrase-learning review feedback so prediction candidates without pinyin do not create empty-pinyin `user_bigrams` rows.
- Bumped the workspace, platform plist build numbers, and package default versions to `0.1.10` for the regenerated macOS installer.
- Deleted the old local macOS `0.1.9` package and generated `dist/macos_imk/PrivatePinyin-0.1.10.pkg` as a local unsigned test installer.

## Current Work

- UPDATE-02 is implemented on `codex/update-02-verified-installer` and is awaiting PR review.
- A package is downloaded only after explicit consent, verified away from the typing thread, and handed to Apple's Installer only after a second confirmation and immediate re-verification.
- The current public stable-manifest endpoint still returns HTTP 404, so a successful live-package end-to-end smoke remains blocked on publisher action and is tracked as `UPDATE-OI-001`.
- UPDATE-03 stale-process detection and reload/logout/restart guidance has not started.

## Validation Results

- Command: `cargo test --workspace`
- Result: passed
- Notes: 67 workspace tests passed with workspace crates reporting version `0.1.10`.

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: No clippy warnings in the Rust workspace.

- Command: `cargo fmt --check`
- Result: passed
- Notes: Formatting is clean after the macOS package refresh.

- Command: `bash scripts/check_stage09_core_sources.sh`
- Result: passed
- Notes: Existing core production-hardening scaffold remains green after adding local short phrase prediction learning.

- Command: `bash scripts/check_macos_imk_sources.sh`
- Result: passed
- Notes: macOS IMK scaffold remains green after the version bump.

- Command: `env CARGO_NET_OFFLINE=true bash scripts/package_macos_pkg.sh`
- Result: passed
- Notes: Built local unsigned test package `dist/macos_imk/PrivatePinyin-0.1.10.pkg`; package signature check reports `Status: no signature`.

### Stage 14 - iOS Signing And App Group Configuration

- Added explicit iOS release inputs for Apple team ID, container app bundle ID, keyboard extension bundle ID, App Group ID, and export-options plist.
- Changed the iOS Xcode project, Info.plist files, and entitlements to inject App Group and bundle identifiers through build settings while keeping local defaults.
- Added `Signing.env.example`, ignored local signing/export plist files, export-options consistency checks, and a Stage 14 source-check script wired into CI.
- Kept `OI-035` open for owner-provided provisioning profiles, App Store metadata, archive/export evidence, and TestFlight validation.

- Command: `git diff --check`
- Result: passed
- Notes: No whitespace or patch formatting issues.

- Command: `bash scripts/check_ios_keyboard_sources.sh`
- Result: passed
- Notes: Existing iOS keyboard scaffold check accepts build-setting injected App Group values.

- Command: `bash scripts/check_stage11_settings_privacy_sources.sh`
- Result: passed
- Notes: Stage 11 privacy/storage gates remain green after the App Group source wiring change.

- Command: `bash scripts/check_stage12_release_sources.sh`
- Result: passed
- Notes: Existing release packaging gates remain green.

- Command: `bash scripts/check_stage14_ios_signing_sources.sh`
- Result: passed
- Notes: Stage 14 signing, bundle ID, App Group, and export-options source gates pass.

- Command: `bash scripts/build_ios_keyboard.sh`
- Result: passed
- Notes: Required sandbox escalation for local Xcode/CoreSimulator access; produced a Debug iOS Simulator build and expanded `PrivatePinyinAppGroupIdentifier` to `group.com.privatepinyin.ios` in both the app and keyboard extension Info.plist files.

- Command: `bash -n scripts/package_ios_app_store.sh scripts/build_ios_keyboard.sh scripts/check_stage14_ios_signing_sources.sh scripts/check_ios_keyboard_sources.sh scripts/check_stage11_settings_privacy_sources.sh`
- Result: passed
- Notes: Shell script syntax is valid.

- Command: `cargo fmt --check`
- Result: passed
- Notes: Rust formatting remains clean.

### Stage 15 - iOS Smoke Readiness

- Added `scripts/run_ios_smoke_readiness.sh` to run source gates, build the iOS Simulator app/extension, and verify built bundle identifiers, App Group expansion, `RequestsOpenAccess=false`, `PrimaryLanguage=zh-Hans`, bundled defaults, and no-network Keyboard Extension Swift sources.
- Added `docs/ios_keyboard_smoke_record.md` to separate automated readiness evidence from the remaining manual Simulator/device keyboard checks.
- Added `docs/ios_release_stage_plan.md` to record the Stage 14-18 iOS release-preparation plan.
- Added `scripts/check_stage15_ios_smoke_sources.sh` and wired it into CI.
- Updated `OI-038` to keep manual keyboard enablement, Notes composition, prediction retention, App Group storage, Globe switching, no Full Access, and password/phone fallback checks open.

- Command: `bash scripts/check_stage15_ios_smoke_sources.sh`
- Result: passed
- Notes: Stage 15 source scaffold, smoke record, platform smoke plan link, and shell syntax checks passed.

- Command: `bash scripts/run_ios_smoke_readiness.sh`
- Result: passed
- Notes: Required sandbox escalation for local Xcode/CoreSimulator access; produced the Debug iOS Simulator app and Keyboard Extension, verified bundle IDs, App Group expansion, `RequestsOpenAccess=false`, `PrimaryLanguage=zh-Hans`, bundled defaults, and no-network Keyboard Extension Swift source usage.

### Stage 16 - TestFlight Archive And Upload

- Added upload-aware `scripts/package_ios_app_store.sh` validation for `ExportOptions.plist` destination, App Store Connect API key inputs, and package summary output.
- Added `platform/ios_keyboard/AppStoreMetadata/ExportOptions.upload.plist.template` for App Store-eligible TestFlight uploads without forcing internal-only distribution.
- Extended `Signing.env.example` and iOS platform docs with App Store Connect API key variables.
- Added `docs/ios_testflight_upload_record.md` to track signed archive/export, uploaded build number, processing status, and TestFlight distribution status.
- Added `scripts/check_stage16_ios_testflight_sources.sh` and wired it into CI.
- Updated `OI-035` to keep real provisioning profiles, signed archive/export, upload, and TestFlight evidence open for Owner credentials.

- Command: `bash scripts/check_stage16_ios_testflight_sources.sh`
- Result: passed
- Notes: Stage 16 upload template, App Store Connect API key gating, package summary, upload record, and CI scaffold checks passed.

- Command: `bash -n scripts/package_ios_app_store.sh`
- Result: passed
- Notes: Shell syntax is valid. The scripted API-key path remains available; build 13 used the signed-in Xcode account, automatic provisioning, and direct `xcodebuild -exportArchive` upload instead.

### Stage 17 - Optimized iOS Keyboard Build 13

- Command: `cargo test --workspace && cargo fmt --all -- --check && cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: All 70 Rust tests passed; formatting and clippy were clean.

- Command: `env DEVELOPER_DIR=/Users/shaola/Downloads/软件/Xcode.app/Contents/Developer bash scripts/run_ios_smoke_readiness.sh`
- Result: passed
- Notes: Beta Xcode reported `BUILD SUCCEEDED`; Stage 14-16 source gates, bundle IDs, App Group expansion, `RequestsOpenAccess=false`, bundled settings, and no-network checks passed.

- Command: iOS 27.0 iPhone 17 Pro Simulator manual smoke
- Result: passed
- Notes: Added `猫栈拼音`, kept Full Access off, verified `nihao -> 你好`, `wojintian -> 我今天`, retained prediction, inline learning opt-in, current-container path repair, Globe switching, and non-overlapping portrait/landscape layouts.

- Command: Beta Xcode Release archive and App Store Connect upload
- Result: passed
- Notes: `dist/ios/PrivatePinyin-build13.xcarchive` reports `0.1.12 (13)` arm64; Xcode reported `Upload succeeded` with delivery UUID `0ba67b28-a10c-437c-9968-456d8ee8d95b`.

- Command: `xcrun altool --build-status --delivery-id 0ba67b28-a10c-437c-9968-456d8ee8d95b --wait ...`
- Result: passed
- Notes: Apple returned `import-status=VALID`, `build-audience-type=APP_STORE_ELIGIBLE`, and `is-on-app-store-connect=true`.

### Stage 17 - Local Trigram TestFlight Build 14

- Command: `cargo test --workspace && cargo fmt --all -- --check && cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: All 83 Rust workspace tests passed; formatting and clippy were clean.

- Command: `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/run_ios_smoke_readiness.sh`
- Result: passed
- Notes: Xcode 27 and the iOS 27 Simulator build passed Stage 14-16 source gates, App Group expansion, `RequestsOpenAccess=false`, bundled settings, and no-network checks.

- Command: iOS 27.0 iPhone 17 Pro Simulator trigram smoke
- Result: passed
- Notes: With Full Access off and local learning enabled, selecting `我 -> 喜欢 -> 猫` created the expected local trigram row; a new `我 -> 喜欢` context then predicted `猫`.

- Command: Xcode 27.0 beta archive and App Store Connect upload
- Result: upload rejected before import
- Notes: App Store Connect no longer accepted build `27A5194q`; no TestFlight build was created from this attempt.

- Command: Xcode 26.6 Release archive and App Store Connect upload
- Result: passed
- Notes: `dist/ios/PrivatePinyin-build14-xcode26.xcarchive` reports `0.1.18 (14)`, iPhoneOS 26.5, and arm64; Xcode reported `Upload succeeded` with delivery UUID `2bcd0055-5594-46bd-aa56-d8193b53ba58`.

- Command: `altool --build-status --delivery-id 2bcd0055-5594-46bd-aa56-d8193b53ba58 --wait ...`
- Result: passed
- Notes: Apple returned `import-status=VALID`, `build-audience-type=APP_STORE_ELIGIBLE`, `build-status=BETA_INTERNAL_TESTING`, and `is-on-app-store-connect=true`.

### macOS 0.1.13 Signed Release Package

- Command: signed `bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and `private-pinyin-notary`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.13.pkg`; Apple notarization submission `edc25310-8b8f-4558-84c3-706bcad40dbb` returned `Accepted`, and stapling succeeded.

- Command: `PRIVATE_PINYIN_VERSION=0.1.13 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: Trusted installer signature, Gatekeeper assessment, stapled ticket, notarytool profile, and SHA-256 validation passed. SHA-256: `9c17738382c030a87db4208ba456e1abcf73545af85bb63a451ea8147ca1451e`.

### macOS 0.1.14 Signed Release Package

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.14 bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and `private-pinyin-notary`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.14.pkg`; Apple notarization submission `9a037028-fae7-46d8-b7ef-8a9801f92571` returned `Accepted`, and stapling succeeded.

- Command: `PRIVATE_PINYIN_VERSION=0.1.14 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: Trusted installer signature, Gatekeeper assessment, stapled ticket, notarytool profile, and SHA-256 validation passed. SHA-256: `30c75e24d8ad9b3356acfc6aa7e50e47fb30e9363f23ac2aad06dbd61b40cd79`.

### macOS 0.1.15 Candidate-Panel Lifetime Fix

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.15 bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and `private-pinyin-notary`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.15.pkg`; Apple notarization submission `e413d75d-d53e-49b5-9918-0c40f20ac5ba` returned `Accepted`, and stapling succeeded.

- Command: `PRIVATE_PINYIN_VERSION=0.1.15 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: Trusted installer signature, Gatekeeper assessment, stapled ticket, notarytool profile, and SHA-256 validation passed. SHA-256: `cb48d25bfd31345ba91f9a9d073a9cf49cabb407d376edaa304b04cffdf59211`.

- Command: installed-upgrade TextEdit/Chrome focus-switch smoke
- Result: passed
- Notes: Verified installed version `0.1.15 (15)`, committed `nihao -> 你好` in Chrome, switched between TextEdit and Chrome 20 times with candidates active or committed, confirmed the process remained alive, and observed no new `PrivatePinyin-*.ips` report beyond the 17-report pre-test baseline.

### macOS 0.1.16 Horizontal Candidate Package

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.16 bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and `private-pinyin-notary`
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.16.pkg`; Apple notarization submission `37ddc538-0be0-4f11-b24c-8ba9968e4220` returned `Accepted`, and stapling succeeded.

- Command: `PRIVATE_PINYIN_VERSION=0.1.16 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: Trusted installer signature, Gatekeeper assessment, stapled ticket, notarytool profile, and SHA-256 validation passed. SHA-256: `678026ab7a6e9c86b284e5048c78fa52fbb59f587954e2f16e33495a1d41a289`. Four-host horizontal layout and number-selection smoke remains required before public release.

### Local Trigram Learning Validation

- Command: `cargo test --workspace`
- Result: passed
- Notes: All Rust, C ABI, layout, settings, prediction, privacy, lexicon-builder, and 28 user-lexicon tests passed, including legacy-schema migration and concurrent SQLite learning updates.

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: C ABI demo returned `你好` and committed it successfully.

- Command: `bash scripts/build_macos_imk.sh`
- Result: passed

- Command: `bash scripts/build_ios_keyboard.sh`
- Result: passed
- Notes: Xcode 27 Simulator build completed with `BUILD SUCCEEDED` after running with CoreSimulator access.

- Command: stage 09/11, platform-validation, macOS, iOS, and Windows source gates
- Result: passed

- Command: GitHub Actions CI run `29180012276` on PR #15
- Result: passed
- Notes: Ubuntu Rust/source gates and the `windows-2022` Rust/TSF job both passed; the Windows job includes the concurrent trigram learning regression that originally exposed SQLite writer starvation.

### macOS 0.1.17 Bounded Trigram Package

- Command: signed `PRIVATE_PINYIN_VERSION=0.1.17 bash scripts/package_macos_pkg.sh` with Developer ID Application and Developer ID Installer, followed by direct `notarytool submit` using the existing local Apple credential
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.17.pkg`; Apple notarization submission `90edbce9-e28f-40a9-9f98-71830dad8839` returned `Accepted`, and stapling succeeded.

- Command: trusted-system `pkgutil --check-signature`, `spctl --assess --type install`, `xcrun stapler validate`, and `codesign --verify --deep --strict`
- Result: passed
- Notes: Developer ID Installer and Application signatures are valid, Gatekeeper reports `Notarized Developer ID`, and SHA-256 is `43bcec63708a16098dec51a6a0d7533795a0cf7b7d459040eb1e9abf449bdb79`.

### macOS 0.1.22 AI-07 Validation Package

- Command: signed and notarized `bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and the `private-pinyin-notary` profile
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.22.pkg`; Apple notarization submission `5b4d744d-9251-4a2d-954d-c8e3415f6769` returned `Accepted`, stapling succeeded, and the full public-release preflight passed.
- SHA-256: `bbe3ab7ef99bb429e4be97fa0230fbfefc35dbde9fd483d7675c135d48e25b92`
- Install smoke: installed over the existing input method; the installed bundle reports `0.1.22 (22)`, its nested dylib passes strict code-signature verification, and Gatekeeper reports `Notarized Developer ID`.
- Host input smoke: TextEdit, Chrome, and Safari each committed `nihao -> 你好`; a 20-cycle rapid TextEdit run produced exactly 20 `你好` commits without a lost or duplicated key. VS Code was not installed on the validation Mac and remains unexecuted.
- Installed-artifact AI smoke: the packaged dylib enabled AI Lite at 8192/16384 MiB, rejected 4096/8191 MiB, preserved five base candidates, and kept secure-input base fallback functional. A 3250-call pressure run completed with 1.734-ms mean, 8.395-ms P95, 8.536-ms P99, and 10.202-ms maximum feed latency.
- Remaining release gates: clean-user install/uninstall, visible horizontal overflow and `1` through `9` candidate selection, VS Code host coverage, website checksum publication, and a real Windows 11 TSF password/pressure smoke.

### Desktop 0.1.23 Lexicon Release Packages

- Command: signed and notarized `PRIVATE_PINYIN_VERSION=0.1.23 bash scripts/package_macos_pkg.sh` with Developer ID Application, Developer ID Installer, and the `private-pinyin-notary` profile
- Result: passed
- Notes: Built `dist/macos_imk/PrivatePinyin-0.1.23.pkg`; Apple notarization submission `9dd8e96f-f94a-464e-8a7c-2cc293765b59` returned `Accepted`, stapling succeeded, Gatekeeper accepted the package as `Notarized Developer ID`, and the full public-release preflight passed.
- macOS SHA-256: `ee057e94e55ac68f4c193d4e4e57967c20f163c88d9f84fa9739381805104e66`
- Release scope: expanded reviewed permissive base lexicon plus upgrade-safe, separately stored local Rime text-dictionary import. A `0.1.23` installed-upgrade smoke remains pending.

- Command: GitHub Actions `Windows Unsigned Package`, run `29688158295`, version input `0.1.23`
- Result: passed
- Notes: The `windows-2022` job built and uploaded NSIS EXE, WiX MSI, and ZIP packages from commit `9931a12`; the downloaded ZIP reports `0.1.23`, includes x64 and x86 TSF components, and carries the matching Simplified Chinese release notes. These Windows artifacts remain unsigned internal-test packages.
- EXE SHA-256: `8ed9510556d14a7744547355881f3cfcfa8b58e5e36db0150ac298cf26f5fa7c`
- MSI SHA-256: `42d46d0f4f3b4733397a511702c8e034b7a8bd96860a4988f32773b27ba85a7f`
- ZIP SHA-256: `70b8d19b2f130e93bec24343674702049616a0c0f3ee727c2e3d5c5e0ccb0496`

### Windows 0.1.13 Unsigned Internal-Test Package

- Command: GitHub Actions `Windows Unsigned Package`, run `29180177697`, version input `0.1.13`
- Result: passed
- Notes: The `windows-2022` job built and uploaded the NSIS EXE, WiX MSI, and ZIP from commit `91b37fa02843b4594a5d043b24675ba4a0912787`; the ZIP contains `ReleaseNotes.zh-Hans.txt` and all TSF runtime files.

- Artifact: `dist/windows_tsf/PrivatePinyin-0.1.13-setup.exe`
- SHA-256: `7bcc0125b1e57aa129a85f773aa5feca543c70a852704b80762440d4615c9b88`
- Artifact: `dist/windows_tsf/PrivatePinyin-0.1.13.msi`
- SHA-256: `992141e002b895b9b4c422f835b9261ccb0ae3dba6e22b01111e65efc7aa5bc8`
- Artifact: `dist/windows_tsf/PrivatePinyin-0.1.13.zip`
- SHA-256: `0f167ca8e923f50c89b89723fa1192b407ce5e69bb4a73b8f3a88bf40211f6a1`
- Distribution note: these Windows artifacts are unsigned and remain for internal testing only.

### Local AI AI-01 Validation

- Command: `bash scripts/check_ai01_evaluation_sources.sh`
- Result: passed
- Notes: Dataset provenance and 20-case manifest checks passed; all 13 required pre-AI regressions passed, while 7 correction/mixed-input opportunities remain intentionally observable and non-blocking.

- Command: `cargo fmt --all -- --check`
- Result: passed

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed

- Command: `cargo test --workspace`
- Result: passed
- Notes: Existing core, C ABI, settings, lexicon, learning, nine-key, and the 6 new AI evaluation/benchmark unit tests passed.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged C ABI still returned and committed `你好`.

- Command: `bash scripts/run_ai_eval.sh --benchmark --initialization-iterations 5 --lookup-iterations 100`
- Result: passed
- Notes: On the arm64 macOS reference machine, engine initialization P95 was 56.01 ms, continuous-pinyin lookup P95 was 1.48 ms, and nine-key lookup P95 was 3.67 ms. Measurements are report-only rather than CI thresholds.

### Local AI AI-02 Validation

- Command: `bash scripts/check_ai02_runtime_contracts.sh`
- Result: passed
- Notes: Required contract files, workspace membership, full request identity, cancellation signature, redacted debug surfaces, provider isolation, and deterministic mock tests passed.

- Command: `cargo fmt --all -- --check`
- Result: passed

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed

- Command: `cargo test --workspace`
- Result: passed
- Notes: Eight AI-02 tests cover deterministic candidate-set hashing, mock repeatability, identity-scoped cancellation, stale-revision rejection, deadline expiry, candidate-hash mismatch, debug redaction, and approved latency classes; existing engine and tool tests also remain green.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged C ABI still returned and committed `你好`; AI-02 is not connected to production input paths.

### Local AI AI-03 Validation

- Command: `bash scripts/check_ai03_privacy_sources.sh`
- Result: passed
- Notes: Required guard/builder/tests exist; runtime source scans found no network client, external AI service, forbidden context field, or content-logging macro.

- Command: `cargo fmt --all -- --check`
- Result: passed

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed

- Command: `cargo test --workspace`
- Result: passed
- Notes: Eighteen local-AI tests cover the eight AI-02 lifecycle cases plus normal/minimized context, secure input, password/OTP, payment/identity/phone data, API-key discussion versus assignment, full-pinyin versus nine-key numeric input, oversized input, policy/hardware/budget rejection, strict privacy, explicit actions, and builder debug redaction.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged C ABI still returns and commits `你好`; AI-03 is not connected to production input paths.

### Local AI AI-04 Validation

- Command: `bash scripts/check_ai04_rules_sources.sh`
- Result: passed
- Notes: Required rule sources and first-party assets exist; source scans found no content logging, network client, or external AI service. The quality gate reports 13/13 required regressions and 7/7 observed opportunities within target.

- Command: `cargo test -p private_pinyin_local_ai_core`
- Result: passed
- Notes: 30 tests cover existing runtime/privacy contracts plus common-confusion, repeated-key, missing-medial, normal-input, two-result limit, validator, canonical-term, multi-term, decodable boundaries, overlong/non-ASCII rejection, debug-redaction, duplicate/stale/invalid cleanup, no-mutation, and strict-privacy behavior.

- Command: `cargo test -p private_pinyin_ai_eval_runner`
- Result: passed
- Notes: The rules-first evaluation test uses the complete 20-case first-party corpus and requires all required and observed targets to pass.

- Command: `bash scripts/run_ai_eval.sh --rules --require-observed-successes 7`
- Result: passed
- Notes: Overall Top-1 is 19/20, all expected candidates are found, and MRR is 0.975. The unchanged production engine remains the fallback and no platform host invokes AI-04 rules.

### Local AI AI-05 Validation

- Command: `bash scripts/check_ai05_model_gate_sources.sh`
- Result: passed
- Notes: The strict schema/template/empty-registry source contract passed, no external AI service or runtime network source was detected, the CLI packaged local synthetic bytes, and no model weight was added to the repository.

- Command: `cargo test -p private_pinyin_local_ai_core -p private_pinyin_model_packager`
- Result: passed
- Notes: Forty-one core tests include valid dual-control loading, manifest-self-approval rejection, bounded corruption checks, use-time replacement, platform, memory tier, unsafe path, local-only privacy, preapproval, empty registry, and symbolic-link cases; two packager tests cover atomic hashing and refusal to manufacture Owner approval.

- Command: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`
- Result: passed
- Notes: The complete workspace remains formatted, warning-free, and green with the committed Cargo lockfile.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged production C ABI still returns and commits `你好`; AI-05 adds no provider, model, FFI change, host integration, setting, or visible input behavior.

### UPDATE-01 macOS Version Check Validation

- Command: `bash scripts/check_update01_sources.sh`
- Result: passed
- Notes: Fixed-host, opt-in, strict-privacy, ephemeral-session, 128-KiB streaming cap, manifest-validation, UI wiring, and offline Swift tests passed.

- Command: `bash scripts/check_macos_imk_sources.sh && bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: The complete Swift InputMethodKit host compiled without warnings and produced `dist/macos_imk/PrivatePinyin.app`.

- Command: local `--show-preferences` and `--show-onboarding` visual smoke
- Result: passed
- Notes: Update status, manual check, automatic opt-in, privacy copy, and existing controls fit without clipping or overlap; the fresh automatic-check state is off.

- Command: `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, and `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged shared engine and C ABI still return and commit `你好`; update code remains isolated to the macOS host.

- Command: `curl -I https://wwwstationcat.org/updates/private-pinyin/macos/stable.json`
- Result: pending publisher action (`HTTP 404` on 2026-07-14)
- Notes: The client and manifest contract are ready, but `UPDATE-OI-001` remains open until the owner publishes and smoke-tests the live stable manifest after an immutable signed/notarized pkg is available.

### UPDATE-02 Verified Package Handoff Validation

- Command: `bash scripts/test_macos_update_package.sh`
- Result: passed
- Notes: Offline Swift tests cover successful verification plus exact-size, SHA-256, Team ID, installer-signature, and notarization failures without requiring a live network endpoint.

- Command: `bash scripts/check_update02_sources.sh`
- Result: passed
- Notes: The source gate pins ephemeral download policy, same-host HTTPS redirects, bounded package size, private cache permissions, exact subprocess arguments, pinned Team ID, notarization, two-step consent, re-verification, and the ban on silent privileged installation.

- Command: `bash scripts/check_update01_sources.sh && bash scripts/check_macos_imk_sources.sh && bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: UPDATE-01 compatibility and the complete Swift InputMethodKit host build passed without warnings.

- Command: `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, and `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The unchanged shared engine and C ABI remain clean and still return and commit `你好`; UPDATE-02 remains isolated to the macOS host.

- Command: local `--show-preferences` update-state visual smoke
- Result: passed
- Notes: The update status and action controls fit the Station Board preferences window without clipping or overlap. A successful live signed-package handoff remains pending `UPDATE-OI-001`.

### Permissive Base + Local Rime Import Validation

- Review hardening preserves a non-empty custom macOS `user_lexicon_path`, reports the accepted row count when a later selected file fails, rejects unavailable iOS security-scoped documents with a precise message, and documents the current sequential batch and damaged-layer recovery contract.
- Executable regressions now prove repeated imports merge cumulatively and a merge beyond 200,000 entries returns `ImportedLexiconLimit` without changing the existing canonical file.
- Command: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace`
- Result: passed
- Notes: The complete workspace is formatted and warning-free. Import tests cover source and canonical size limits, cumulative merge, byte-preserving limit failure, explicit-pinyin parsing, deduplication, malformed-layer fail-soft loading, independent storage, and new-engine visibility; the production input regressions remain green against the 137,699-entry base.

- Command: `cargo clippy -p private_pinyin_ime_ffi --all-targets --features desktop-ai -- -D warnings` and `cargo test -p private_pinyin_ime_ffi --features desktop-ai`
- Result: passed
- Notes: The optional AI-07 desktop FFI remains compatible with the expanded engine settings and import ABI; secure-mode, stale-result, and candidate-permutation tests remain green.

- Command: `bash scripts/check_local_lexicon_import_sources.sh`, `bash scripts/check_stage13_lexicon_sources.sh`, and `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: The bounded CLI import/clear smoke produced one canonical row, the approved manifest reports exactly 137,699 base entries, and the unchanged C demo still commits `你好`.

- Command: `bash scripts/check_macos_imk_sources.sh`, `bash scripts/check_windows_tsf_sources.sh`, `bash scripts/check_installers_settings_sources.sh`, and `bash scripts/check_ios_keyboard_sources.sh`
- Result: passed
- Notes: All three hosts expose the isolated import layer while preserving platform privacy contracts. iOS source gates pin the document picker, container-side Rust import into the App Group, and a read-only keyboard extension so Full Access remains unnecessary.

- Command: `bash scripts/build_macos_imk.sh`
- Result: passed
- Notes: The complete InputMethodKit app compiles successfully with the expanded bundled base and hardened local import controls.

- Command: Beta Xcode `scripts/build_ios_keyboard.sh` plus `scripts/test_ios_chinese_transform.sh`
- Result: passed (`BUILD SUCCEEDED`)
- Notes: The iOS container App and Keyboard Extension compile with the isolated C import bridge, partial-import status, and security-scoped document handling; the standalone Chinese conversion regression also remains green.

### Desktop 0.1.24 macOS Public Package Validation

- Command: `PRIVATE_PINYIN_VERSION=0.1.24 bash scripts/package_macos_pkg.sh`
- Result: passed
- Notes: The app and dormant AI-09 Helper were signed with `Developer ID Application`; the pkg was signed with `Developer ID Installer`, submitted to Apple, accepted under submission `54645912-7b0d-4d83-b670-453067f3897f`, and stapled successfully.

- Command: `PRIVATE_PINYIN_VERSION=0.1.24 bash scripts/check_macos_public_release.sh`
- Result: passed
- Notes: The trusted installer signature, Gatekeeper `Notarized Developer ID` assessment, stapled ticket, notary profile, and package checksum all passed. Artifact: `dist/macos_imk/PrivatePinyin-0.1.24.pkg` (`3,800,887` bytes); SHA256 `ff0d2d73e0ee63daf06ac052b5a06cf7a17df309ae7d1713c0867d09d832fc7d`.

- Release scope: macOS clients now share one immutable engine snapshot while retaining independent session state. Installed multi-client resident-memory and upgrade smokes remain manual release gates; the AI-09 Helper remains dormant and does not alter normal input behavior.

## Open Items

- Select the final project license before external reuse or release.
- Keep production runtime data outside source directories.
- Refine Shift toggle semantics in platform hosts.
- Provide Windows code-signing certificate and signed binary/MSI/PowerShell-script evidence.
- Validate signed Windows MSI install/uninstall on Windows 11.
- Validate TSF DLL loading and Notepad smoke test on Windows 11.
- Add TSF display attributes for preedit text.
- Validate signed/notarized macOS pkg install/uninstall and release uninstall guidance.
- Polish macOS candidate positioning and appearance.
- Verify IMK candidate panel number-key routing on macOS.
- Validate Windows installer and settings UI on Windows 11.
- Submit build `0.1.21 (17)` to the external TestFlight group, monitor Beta App Review, and publish tester access after approval.
- Run real-device smoke tests in Notes, Safari, password, and phone fields, including Full Access-off App Group behavior and local learning persistence under distribution provisioning.
- Expose sanitized core logging through host ABI callbacks.
- Measure production lexicon engine initialization latency on macOS, Windows TSF, and iOS inline-settings reload before deciding whether precompiled data, lazy loading, or a runtime settings API is needed.
- Replace the 20-entry starter bigram predictor with a licensed production prediction data source.
- Capture Windows, Intel macOS, and real-device iOS latency and resident-memory baselines before calibrating AI Lite budgets.
- Detect and calibrate trustworthy memory/GPU profiles on macOS, Windows, and iOS before host model integration.
- Publish and smoke-test the fixed macOS stable manifest after the versioned pkg and release page are live.

## Files Changed In Latest Stage

- `ime_core/assets/base_lexicon.tsv`
- `ime_core/assets/lexicon_manifest.json`
- `ime_core/src/imported_lexicon.rs`
- `ime_core/src/lexicon.rs`
- `ffi/c_api.h`
- `ffi/ime_ffi/src/lib.rs`
- `platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift`
- `platform/windows_tsf/installer/open-settings.ps1`
- `platform/ios_keyboard/ContainerApp/ContentView.swift`
- `platform/ios_keyboard/ContainerApp/IosSettingsStore.swift`
- `platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift`
- `docs/local_rime_lexicon_import.md`
- `scripts/check_local_lexicon_import_sources.sh`

## Next Step

- Review AI-08, then run its real-device latency, resident-memory, memory-pressure, secure-field,
  numeric/phone, stale-result, and queue-saturation smoke before release approval. Keep the current
  8-GiB AI-05 policy unchanged until those measurements support a separately reviewed threshold.
