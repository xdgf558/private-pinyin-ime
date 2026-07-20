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
Consequences: Windows candidate-positioning and popup lifecycle open items can close once Windows CI compiles. Full TSF display attributes and app-by-app runtime smoke validation remain tracked separately; macOS menu icon assets were later closed by the icon refresh.

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
Consequences: The Rust core now embeds active `base_lexicon.tsv` and `bigram.tsv` starter assets. `tools/lexicon_builder` can convert local project TSV or CC-CEDICT-style files into the project format and write an audit manifest, but generated production data is not release-ready unless the manifest is explicitly marked approved after owner review. `OI-001` remained open until Decision 019 selected and imported approved production data.

## Decision 017: macOS input source default state

Date: 2026-07-07
Status: accepted
Decision: Keep the macOS input mode `tsInputModeDefaultStateKey` set to `false`.
Reason: Local System Settings debugging showed that marking a third-party input mode default-enabled can make it disappear from the add-input-source selector even when the bundle is installed and localized correctly. The actual `.pkg` install path must be smoke-tested by finding `猫栈拼音` under Simplified Chinese and typing `nihao -> 你好`.
Consequences: Future TIS metadata edits must preserve this value unless a replacement registration strategy is validated through the real package install path, not only a temporary per-user test bundle.

## Decision 018: macOS duplicate input-source cleanup

Date: 2026-07-08
Status: accepted
Decision: Treat repeated PrivatePinyin rows in System Settings as stale enabled-input-source records, not as a reason to change the input mode script metadata away from `smSimpChinese`.
Reason: Local cleanup showed `AppleEnabledInputSources` / `AppleEnabledThirdPartyInputSources` can retain records created by older `tsInputModeDefaultStateKey=true` builds and manual `TISEnableInputSource` diagnostics. Cleaning those user preference records removed the repeated rows without requiring a metadata change.
Consequences: Do not use `TISEnableInputSource` as part of normal macOS smoke tests. macOS package validation must include a consecutive-upgrade check that confirms System Settings and the menu bar input menu show at most one PrivatePinyin entry.

## Decision 019: Production base lexicon source

Date: 2026-07-08
Status: accepted
Decision: Use Android Open Source Project PinyinIME `rawdict_utf16_65105_freq.txt` as the production phrase lexicon source and supplement it with mozillazg pinyin-data single-character readings.
Reason: AOSP PinyinIME provides a broad phrase dictionary with frequencies under Apache-2.0, and pinyin-data provides broad single-character reading coverage under MIT. Together they solve the immediate usability gap where common phrases such as `ganma -> 干嘛` were missing while keeping licensing compatible with the repository's all-rights-reserved application code.
Consequences: `tools/lexicon_builder` now supports `aosp-rawdict` and `pinyin-data` imports, the active base lexicon has 100,657 entries, `THIRD_PARTY_NOTICES.md` records upstream notices, and `OI-001` is closed for the current bundled base dictionary. Future third-party bigram or lexicon replacements must still update the manifest and notices before release approval.

## Decision 020: Stage 14 iOS signing configuration boundary

Date: 2026-07-09
Status: accepted
Decision: Keep source-tree iOS signing and App Group values configurable through build settings and owner-filled local files instead of committing release credentials, bundle identifiers, or provisioning profile names.
Reason: iOS release readiness needs Apple Developer team ownership, App Group capabilities, and provisioning profiles, but those values differ by owner account and should not be silently hard-coded into project source. The repo should make the required inputs explicit and fail early when export options do not match the configured app and keyboard bundle IDs.
Consequences: `scripts/package_ios_app_store.sh` now requires explicit team, app bundle, keyboard bundle, App Group, and export-options inputs. The Xcode project and entitlements use `PRIVATE_PINYIN_IOS_*` build settings with local defaults. `OI-035` remains open until real provisioning profiles, App Store metadata, archive/export evidence, and TestFlight smoke evidence are provided.

## Decision 021: Stage 15 iOS smoke validation boundary

Date: 2026-07-09
Status: accepted
Decision: Split iOS validation into automated smoke-readiness checks that run from the repository and manual keyboard behavior checks that must be performed in Simulator or on a device.
Reason: Xcode can verify build products, Info.plist expansion, App Group configuration, `RequestsOpenAccess=false`, bundled settings, and Keyboard Extension no-network source posture, but iOS keyboard enablement, Notes input, prediction retention, Globe switching, and password/phone fallback depend on system UI behavior.
Consequences: `scripts/run_ios_smoke_readiness.sh` provides repeatable automated readiness evidence, while `docs/ios_keyboard_smoke_record.md` tracks the remaining manual smoke checklist. `OI-038` remains open until the manual Simulator/device checks are completed with evidence.

## Decision 022: Stage 16 TestFlight upload boundary

Date: 2026-07-09
Status: accepted
Decision: Support both local App Store export and App Store Connect upload through the same package script, with upload mode requiring explicit App Store Connect API key inputs and an owner-updated TestFlight record.
Reason: TestFlight upload is release-sensitive and should not depend on whatever Xcode account happens to be logged into a developer machine. The repository can validate script wiring and required inputs, but only the owner can provide provisioning profiles, App Store Connect credentials, and post-upload build status.
Consequences: `scripts/package_ios_app_store.sh` validates `ExportOptions.plist` destination, team ID, provisioning profile mappings, and App Store Connect API key variables before upload. `docs/ios_testflight_upload_record.md` remains pending until a signed archive is uploaded and the build appears in App Store Connect.

## Decision 023: Second-generation continuous-pinyin decoding

Date: 2026-07-11
Status: accepted
Decision: Decode continuous pinyin as a bounded word lattice over normalized raw-character offsets, score paths with logarithmic unigram frequency plus base and local-user bigram transitions, and retain the chosen word segments for local transition learning.
Reason: The first implementation selected a small set of syllable parses before a separate phrase DP and summed raw frequencies, so an early syllable prune or several individually frequent words could defeat a more natural sentence. The shared Rust core must resolve pinyin and word boundaries together without adding network processing or changing the platform ABI.
Consequences: macOS, Windows, and iOS receive the same beam decoder through the existing C ABI. Selected continuous candidates teach their internal adjacent word transitions only when learning is enabled and strict privacy mode is off. The active base bigram remains the licensed-data follow-up in `OI-043`; incremental prefix caching and mixed full-pinyin/initial input remain in `OI-045`.

## Decision 024: macOS candidate-panel ownership

Date: 2026-07-11
Status: accepted
Decision: Own the server-attached `IMKCandidates` panel at process scope and share it across all `IMKInputController` client sessions.
Reason: InputMethodKit creates a controller for each client session but retains candidate-panel integration at the `IMKServer` level. Releasing a controller-owned panel during focus changes left the server with a stale Objective-C reference; repeated deactivation crashed in `objc_msgSend` while querying `isVisible`, causing intermittent input loss until macOS restarted the input method.
Consequences: Controllers may hide the shared panel and reset their own composition state, but they must not determine its lifetime. macOS smoke testing must repeatedly switch among clients with both visible and hidden candidates and verify that no new crash report appears.

## Decision 025: Bounded local trigram learning

Date: 2026-07-12
Status: accepted
Decision: Learn selected-token trigrams in the existing local SQLite user lexicon, rank all learned signals with a 30-day inactivity half-life, retain only the eight most recent session tokens, and enforce fixed row limits with decayed-weight eviction.
Reason: Two-token context distinguishes common continuations that a one-step bigram cannot, while local decay and bounded storage keep stale habits from dominating forever and prevent long-running installations from growing without limit. The feature must preserve the no-network and no-full-sentence privacy boundary.
Consequences: macOS, Windows, and iOS receive the same trigram behavior through the existing Rust core and C ABI. The database may store a bounded `(first, second, next)` selected-token relation and next-token pinyin, but never raw keys, surrounding document text, or an unbounded sentence. Default limits are 20,000 phrases, 20,000 bigrams, 10,000 short phrases, and 20,000 trigrams; `OI-044` is closed.

## Decision 026: Evaluation-first local AI development

Date: 2026-07-14
Status: accepted
Decision: Freeze deterministic quality and reference latency before adding any local AI provider, keep existing input behavior as required regression cases, and track unsupported typo correction, mixed English, and mixed full-pinyin/initial input as non-blocking observation cases.
Reason: A provider cannot be judged safely without a pre-AI baseline, and making model integration precede evaluation would hide regressions behind subjective examples. The corpus must remain first-party synthetic or derived from public repository regressions; exported user data and real application context are prohibited.
Consequences: AI-01 adds development tools and CI checks only. Future AI stages must improve the observed set without regressing required cases, must measure platform latency/memory separately, and must not asynchronously change the identity of already visible numbered candidates.

## Decision 027: Opt-in macOS update discovery

Date: 2026-07-14
Status: accepted
Decision: Implement UPDATE-01 in the thin macOS host as an opt-in, check-only client for one fixed first-party HTTPS manifest; keep automatic checks off by default, pause them in strict privacy mode, and leave the shared Rust input engine network-free.
Reason: Website-distributed users need a reliable way to discover signed releases, but version discovery must not quietly weaken the project's no-network default or combine unreviewed download, privilege, and process-restart behavior in one step.
Consequences: The menu, preferences, and first-run guide expose update controls; manifest parsing rejects foreign hosts and malformed package metadata; failures never block typing. UPDATE-02 must separately verify and hand a signed/notarized pkg to macOS Installer, while UPDATE-03 owns stale input-method process guidance.

## Decision 028: Verified macOS package handoff

Date: 2026-07-14
Status: accepted
Decision: Download a macOS update only after explicit user consent, verify exact size and SHA-256 plus the pinned Developer ID Installer Team ID and Gatekeeper notarization, repeat verification immediately before handoff, and open the package only with Apple's visible system Installer.
Reason: A trusted manifest alone cannot prove that bytes received later are the reviewed release, and an input-method process must not silently cross a privilege boundary. The update flow must fail closed if the package, signer, notarization result, local cache, or system verifier differs from the published contract.
Consequences: UPDATE-02 adds a constrained ephemeral download session, one-package private cache, fixed-path system verification without shell evaluation, sanitized failure states, cancellation/retry UI, and two visible consent points. The host never invokes the privileged `installer` command or supplies credentials. UPDATE-03 remains responsible for post-install process-refresh guidance.

## Decision 029: Consent-Based macOS Process Refresh

Date: 2026-07-15
Status: accepted
Decision: Launch the installed bundle's signed executable as a dedicated UI-only process after pkg installation, detect stale 猫栈拼音 processes by exact bundle identifier plus pre-install launch time, and request a normal exit only after explicit user consent and PID revalidation.
Reason: Replacing an input-method bundle does not replace code already loaded by macOS, while broad process killing, automatic logout, or routine restart prompts would risk active work in unrelated applications. Direct launch in the console user's Aqua session also avoids both activation of an old instance and LaunchServices `kLSNoExecutableErr` for Input Method bundles.
Consequences: Command-line onboarding, preferences, and post-install helpers do not create an `IMKServer`. A successful normal refresh needs only an input-source switch; a process that remains receives logout/login guidance. No force-termination, automatic logout, automatic restart, or unrelated-application action is permitted.

## Decision 030: Identity-Bound Local AI Runtime Contracts

Date: 2026-07-15
Status: accepted
Decision: Establish a zero-dependency `local_ai_core` contract before adding privacy policy, models, or platform integration; identify every request and response by opaque session ID, request ID, composition revision, and ordered candidate-set hash, and scope cancellation to that complete identity.
Reason: Local inference will eventually be asynchronous, so a request ID alone cannot prevent a late result from a previous composition, reordered candidate page, or different client session from being applied. A deterministic mock and monotonic deadline make these lifecycle rules testable before any provider or host can obscure them.
Consequences: AI-02 adds feature/hardware/budget contracts, redacted content-bearing debug output, sanitized error codes, deadline handling, identity validation, and a mock provider only. The FNV candidate-set fingerprint is restricted to in-request lifecycle identity and must not be reused as a persistent or cross-process cache key. It does not change input behavior or touch the engine, FFI, or platform hosts. AI-03 must add PrivacyGuard and minimal-context enforcement; AI-07 must supply trustworthy host revisions, invoke the synchronous provider only through bounded worker queues, and discard responses whose complete identity is no longer current.

## Decision 031: Guarded and Minimal Local AI Requests

Date: 2026-07-16
Status: accepted
Decision: Make `AiRequestBuilder` plus `PrivacyGuard` the only public local-AI request construction path; fail closed for secure, sensitive, oversized, disabled, unlicensed, unsupported, over-budget, or non-consensual explicit-action input; and retain at most the last eight non-empty context tokens.
Reason: A private model does not make an overbroad request safe. Minimizing the type itself prevents accidental clipboard/document context collection, while pre-inference rejection and code-only errors keep secrets out of providers and diagnostics. Candidate pages are rejected rather than truncated so the lifecycle hash always describes the exact visible ordered set.
Consequences: AI-03 adds no model or production integration. Runtime source gates reject network/external-service dependencies and content logging. Lightweight AI may be explicitly permitted in strict privacy mode, while policy can disable all AI there. Raw input explicitly distinguishes full pinyin from nine-key digits so OTP heuristics do not disable normal nine-key composition. AI-07 must still provide trustworthy platform secure-input signals and dispatch accepted requests asynchronously.

## Decision 032: Session-Local Incremental Mixed-Pinyin Decoding

Date: 2026-07-16
Status: accepted
Decision: Keep one bounded continuous-decoder lattice per input session, reuse only the unchanged raw-character prefix while context and apostrophe boundaries remain compatible, and decode exact full-pinyin and initial edges in the same beam with an explicit abbreviation penalty.
Reason: Rebuilding every lattice position after each key repeats deterministic work, while a separate shorthand lookup cannot express mixed forms such as `wojt`. Reuse must remain session-local because path scores depend on the current context and learned transition snapshot, and permissive shorthand paths must not reinterpret ordinary raw English such as `abc`.
Consequences: Appending input extends only new lattice suffix positions, backspace truncates to a reusable prefix, and commit/cancel/reset/mode changes clear the cache. Mixed paths require at least two characters of full pinyin, rank below equivalent full-pinyin paths, and continue to use the existing bounded beam and lexicon indexes. macOS, Windows, and iOS receive the behavior through the unchanged C ABI; no cache is persisted or shared across sessions or processes, and AI development remains paused.

## Decision 033: Rules-First Local Enhancement Before Model Integration

Date: 2026-07-17
Status: accepted
Decision: Implement AI-04 as deterministic, bounded, host-independent rules: at most two validated pinyin corrections, canonical first-party English-term segmentation, and read-only reason-coded user-lexicon cleanup suggestions.
Reason: The P0 correction and mixed-English cases can be improved measurably without introducing model provenance, package size, asynchronous lifecycle, or input-thread latency risks. Cleanup must remain advisory because silently deleting learned data would violate user control and make recovery impossible.
Consequences: The offline rules evaluation passes all 13 required regressions and all 7 observed targets. Correction never removes the original path; normal pinyin such as `zhongguo` produces no correction. Stateless correction and term matching may be permitted in strict privacy mode, while cleanup is disabled there. No host, FFI, or production engine path invokes these rules before AI-07 adds bounded worker queues, trustworthy revisions, and stale-result rejection; user-confirmed deletion and undo remain integration work.

## Decision 034: Dual-Control Local Model Supply Chain

Date: 2026-07-17
Status: accepted
Decision: Require every local model package to pass a strict manifest plus an exact, independently embedded Owner approval fingerprint; treat a manifest's own approval flag as necessary but never sufficient, and keep the default approval registry empty.
Reason: Model weights are executable product inputs with separate provenance, license, privacy, platform, size, and hardware risks. A package must not authorize itself, a renamed or replaced artifact must invalidate approval, and a filesystem path must not escape the reviewed package through traversal or symbolic links.
Consequences: AI-05 adds streaming SHA-256/size verification, bounded relative paths, symlink rejection, platform and hardware gates, local-only privacy declarations, use-time primary-model revalidation, a 64-MiB AI Lite package ceiling, an atomic packager that cannot grant approval, and CI checks that reject bundled weights in the empty-registry stage. No model or host integration is added. AI-06 must submit exact artifact provenance and measurable evaluation evidence before the Owner can add a registry entry; AI-07 and AI-08 must provide calibrated host hardware profiles.

## Decision 035: First-Party Fixed-Point AI Lite Ranker

Date: 2026-07-17
Status: accepted
Decision: Implement AI-06 as a shared Rust fixed-point linear ranker over bounded base-order, frequency, segmentation, bigram, trigram, typo-correction, and English-term signals; approve only the exact first-party 426-byte coefficient package whose AI-05 fingerprint and offline quality evidence are reviewed in this stage. Require explicit ranker and feature-schema versions so future feature additions cannot silently reuse incompatible coefficients.
Reason: Existing engine signals already capture useful lexical and local-context evidence, so a tiny deterministic scorer can improve ordering without a neural runtime, network service, opaque training corpus, floating-point platform drift, or a second learning store. Repository regressions and first-party synthetic cases are sufficient to calibrate this first model without using user data.
Consequences: The approved package fingerprint is `8bc7977a88f64a818fd232b7cfafd19af477232259e700d690ea37dfa639d439`; any byte or policy change requires a new version, evaluation, and Owner approval. The 12-case gate improves all eight targeted ranks, preserves all four base winners, and bounds requests to 32 candidates, three outputs, a 64-KiB model file, and 256 cancellation identities. Extreme score/rank inputs are covered by overflow regressions. AI-OI-002 is closed, while AI-OI-009 requires broader non-user benchmark evidence before host integration. No host, FFI, setting, or visible input behavior changes in AI-06; AI-07 must invoke the synchronous provider only on bounded worker queues and discard stale results by complete request identity.

## Decision 036: Licensed Default Coverage Plus Isolated Local Imports

Date: 2026-07-19
Status: accepted
Decision: Ship only reviewed permissive dictionary data in the immutable base lexicon, and support user-selected Rime YAML dictionaries through a bounded, local-only imported layer stored separately from both the base asset and learned SQLite data.
Reason: Every installation needs stable phrase coverage without a setup step, while advanced users may already maintain Rime dictionaries whose licenses are incompatible with redistribution in this all-rights-reserved repository. Combining those concerns into one asset would either weaken default coverage or create licensing and upgrade-loss risks.
Consequences: The bundled base grows to 137,699 entries using MIT phrase-pinyin-data at a low supplemental frequency. rime-ice and other GPL dictionaries are never packaged by the project; users may import their own copies and remain responsible for upstream terms. Imports require explicit pinyin rows, are capped at 16 MiB per source and 200,000 retained entries, use atomic writes, survive upgrades, and can be cleared without touching bundled or learned data. macOS and Windows expose direct import controls. On iOS, the container App invokes the same Rust importer while it owns security-scoped access and writes the App Group layer; the keyboard extension is a read-only consumer, preserving the no-Full-Access posture. App Group failure disables importing without affecting typing.

## Decision 037: Isolated and Optional iOS AI Lite

Date: 2026-07-19
Status: accepted
Decision: Integrate only the AI-05-approved 426-byte fixed-point Lite ranker into the iOS Keyboard Extension behind an isolated `ios-ai` FFI feature, reuse the AI-07 bounded non-blocking worker and stale-result checks, and make every initialization, privacy, memory, queue, deadline, or identity failure preserve ordinary input and candidate order.
Reason: iOS can benefit from the same deterministic candidate signals without a second model, runtime, or learning store, but a Keyboard Extension has a tighter and less predictable memory budget than desktop hosts. Full Access, network processing, surrounding-document collection, synchronous UI-thread inference, and a heavy neural model are incompatible with the product's privacy and responsiveness boundary.
Consequences: The extension stays `RequestsOpenAccess=false`, performs a process-available-memory precheck, applies the approved physical-memory policy, and fails closed for numeric/phone traits while relying on iOS to replace third-party keyboards in secure fields. Simulator builds and deterministic fallback behavior are automated. The existing 8-GiB manifest requirement is deliberately unchanged because changing it would alter the approved policy fingerprint; lowering it requires real-device latency/RSS/memory-pressure evidence and a separately reviewed model-policy update.

## Decision 038: Explicit Verified iOS Upstream Lexicon Import

Date: 2026-07-20
Status: accepted
Decision: Keep the bundled base lexicon permissively licensed and unchanged, while allowing the iOS container App to download a small reviewed `rime-ice` subset only after a visible user confirmation. Pin the upstream release, file paths, byte counts, and SHA-256 values; keep the keyboard extension network-free and store imported data in the existing separate App Group layer.
Reason: Most users need stable offline defaults, while advanced users may choose broader GPL vocabulary without making that data part of the all-rights-reserved application package. A moving branch or background download would weaken provenance, consent, reproducibility, and the project's no-network-by-default promise. The direct download is intended for users on networks that can reach GitHub; users in mainland China or other GitHub-restricted networks should use the existing document-picker path with locally obtained files. This boundary prevents an unofficial mirror from weakening provenance and redistribution constraints.
Consequences: The optional action imports only `8105.dict.yaml`, `41448.dict.yaml`, and `others.dict.yaml` from official `rime-ice` release `2026.03.26`; larger upstream dictionaries exceed the existing per-source or retained-entry policy and are not fetched. The download uses an ephemeral session, fixed HTTPS hosts, exact size and SHA-256 checks, no cookies or input-derived parameters, and temporary files removed after completion. The UI names the GPL-3.0-only source before consent. No `rime-ice` bytes enter the repository, app bundle, installer, or automatic update path. Disabling or never invoking the action preserves the fully offline keyboard behavior. If the upstream tag or files change, pinned integrity checks fail closed until a new Owner-reviewed release updates the evidence and application constants.

## Decision 039: Authenticated Desktop AI Helper Boundary

Date: 2026-07-20
Status: accepted
Decision: Establish AI-09 as a dormant, separately signed desktop helper with one shared bounded binary protocol, per-launch authentication, platform-local process ownership, health checks, cancellation, crash recovery, graceful shutdown, and a ten-minute idle exit. Keep ordinary input and AI Lite ranking entirely in-process and independent of this helper.
Reason: Future completion, rewrite, or translation experiments may require a larger runtime whose startup, memory, cancellation, or crash behavior is unsuitable inside macOS IMK or Windows TSF host processes. A reviewed process boundary must exist before evaluating such a runtime, but a localhost server or broadly accessible IPC endpoint would create unnecessary privacy and impersonation risk.
Consequences: macOS uses anonymous pipes to a controlled bundled child; Windows uses a random unidirectional request/response named-pipe pair protected by current-user-only DACLs and remote-client rejection. The two Windows pipe objects avoid synchronous read/write serialization while retaining one authenticated local channel. Both platforms require a fresh 256-bit token before accepting any command. Payloads, active work, and response queues are bounded; frames and errors never log content; the helper has no network or persistent request cache. Helper absence, timeout, crash, or protocol failure means only that the optional enhancement is unavailable. AI-10 and AI-11 may add real payloads only behind `PrivacyGuard`, explicit feature consent, background dispatch, complete request identity, deadlines, cancellation, stale-result rejection, and separate model approval.

## Decision 040: Record AI-10 Writer Candidate as No-Go

Date: 2026-07-21
Status: accepted
Decision: Pin and evaluate the exact Qwen2.5 0.5B Instruct Q4_K_M artifact at revision `9217f5db79a29953eb74d5343926648285ec7e67` with official llama.cpp release `b10069`, but keep Owner approval and redistribution disabled and record a `NoGo` release decision. Store no model/runtime binaries and do not connect the probe to the AI-09 Helper or any input host.
Reason: AI-10 exists to answer feasibility questions with reproducible evidence rather than to make a predetermined model pass. The candidate's Apache-2.0 provenance, roughly 502-MiB model-plus-runtime download footprint, 579-MiB measured peak RSS, 276-295-ms first-byte latency, and immediate cancellation are technically workable on the development Mac. However, it passed only two of three first-party Chinese quality cases and failed to make a direct scheduling request polite, so it does not meet the Writer quality gate.
Consequences: The checked-in report contains only metrics, result codes, output lengths, artifact identity, and the decision; prompts and generated text remain absent. This candidate cannot enter the AI-05 approval registry, application bundle, installer, Helper, or product UI. AI-11 is blocked on selecting a stronger candidate that passes a new exact-hash evaluation and receives separate Owner redistribution approval. Quality gates must not be weakened merely to convert this result to Go.
