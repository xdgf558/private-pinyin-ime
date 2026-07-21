# Scripts

This directory contains project scripts.

Current scripts:

- `run_c_demo.sh`: builds the FFI library, checks C ABI layout, and runs the C demo.
- `check_windows_tsf_sources.sh`: verifies the Windows TSF source scaffold on non-Windows CI.
- `build_windows_tsf.ps1`: builds the Rust FFI library and Windows TSF DLL on Windows.
- `package_windows_tsf.ps1`: stages Windows installer files, optionally signs DLL/EXE/MSI artifacts, and builds a zip bundle, an EXE setup installer when NSIS is installed, and an MSI when WiX is installed.
- `.github/workflows/windows-package.yml`: manually builds unsigned Windows internal-test zip/EXE/MSI artifacts on a Windows runner.
- `check_macos_imk_sources.sh`: verifies the macOS InputMethodKit source scaffold and bundle plist.
- `build_macos_imk.sh`: builds the Rust FFI library and local macOS InputMethodKit app bundle.
- `test_macos_shared_engine.sh`: compiles a native Swift regression that creates 24 isolated macOS client sessions, verifies they share one parsed engine snapshot, and can optionally report peak RSS with `PRIVATE_PINYIN_REPORT_PEAK_RSS=1`.
- `package_macos_pkg.sh`: builds a macOS `.pkg` installer with a post-install onboarding window, and optionally signs/notarizes it when Developer ID and notarytool settings are provided.
- `check_macos_public_release.sh`: verifies that a macOS `.pkg` is ready for website distribution by checking Developer ID identities, installer signature, Gatekeeper assessment, stapled notarization, notarytool profile access, and SHA256 output.
- `check_installers_settings_sources.sh`: verifies Stage 6 installer and settings scaffold files.
- `build_ios_keyboard.sh`: builds the Rust iOS static library and the iOS container app/keyboard extension.
- `package_ios_app_store.sh`: builds an iOS device archive and exports it with owner-provided App Store signing options.
- `run_ios_smoke_readiness.sh`: builds the iOS simulator app and verifies automated smoke-readiness gates before manual keyboard testing.
- `check_ios_keyboard_sources.sh`: verifies the iOS keyboard source scaffold, plist privacy defaults, and Xcode project wiring.
- `check_local_lexicon_import_sources.sh`: validates bounded local Rime import, separate upgrade-safe storage, platform entry points, and a CLI import/clear smoke test.
- `test_macos_imported_lexicon_source.sh`: compiles and runs the macOS source-label resolver regression for rime-ice/雾凇 and custom Rime dictionary filenames.
- `check_platform_validation_sources.sh`: verifies Stage 8 platform smoke-test documentation and Windows TSF CI wiring.
- `check_stage09_core_sources.sh`: verifies Stage 9 core hardening for indexed lookup, paging, ranking, logging, and lexicon data policy.
- `check_stage10_platform_host_sources.sh`: verifies Stage 10 Windows/macOS host polish sources.
- `check_stage11_settings_privacy_sources.sh`: verifies Stage 11 default-template, privacy, iOS App Group, mode-state, and Globe-key wiring.
- `check_stage12_release_sources.sh`: verifies Stage 12 release packaging, signing hooks, macOS public-release preflight, App Store metadata templates, and update-strategy documentation.
- `check_stage13_lexicon_sources.sh`: verifies Stage 13 production lexicon assets, AOSP/pinyin-data import tooling, third-party notices, and manifest release approval.
- `check_stage14_ios_signing_sources.sh`: verifies Stage 14 iOS signing, bundle ID, export-options, and App Group build-setting wiring.
- `check_stage15_ios_smoke_sources.sh`: verifies Stage 15 iOS smoke-readiness script and record coverage.
- `check_stage16_ios_testflight_sources.sh`: verifies Stage 16 TestFlight archive/upload script, templates, and record coverage.
- `run_ai_eval.sh`: runs the AI-01 baseline, AI-04 rules gate, AI-06 ranker comparison, or the report-only release benchmark.
- `test_macos_update_manifest.sh`: compiles and runs the UPDATE-01 manifest/version validation tests when `swiftc` is available.
- `check_update01_sources.sh`: verifies the UPDATE-01 fixed-host, opt-in, strict-privacy, UI, manifest-validation, and documentation contract.
- `test_macos_update_package.sh`: compiles and runs the macOS UPDATE-02 size, SHA-256, Developer ID, and notarization verifier tests.
- `check_update02_sources.sh`: verifies the UPDATE-02 constrained download, local verification, explicit-consent, and system Installer handoff contract.
- `check_ai01_evaluation_sources.sh`: validates the synthetic/project-regression corpus, data-policy manifest, tools, and required baseline behavior.
- `check_ai02_runtime_contracts.sh`: validates the isolated local AI request/response contracts, budgets, revision identity, cancellation scope, redacted debug surfaces, and deterministic mock provider.
- `check_no_external_ai_service.sh`: rejects network clients, localhost dependencies, cloud AI APIs, and external local model services from local AI runtime sources.
- `check_ai_privacy_sources.sh`: validates guarded request construction, minimal context, sensitive-input rejection, code-only errors, forbidden-context absence, and no runtime content logging.
- `check_ai03_privacy_sources.sh`: runs the complete AI-03 privacy and no-network gate.
- `check_ai04_rules_sources.sh`: validates bounded pinyin correction, canonical English-term preservation, read-only lexicon cleanup suggestions, and the rules-first quality gate.
- `check_ai05_model_gate_sources.sh`: validates strict model manifests, every external Owner approval, SHA-256/size/path/symlink/platform/hardware/privacy gate, and the model packager.
- `check_ai06_lite_ranker_sources.sh`: validates the approved fixed-point ranker package, bounded runtime, first-party dataset declarations, and the 8-improvement/zero-regression quality gate.
- `check_ai09_desktop_helper_sources.sh`: validates the AI-09 bounded local protocol, authenticated desktop Helper boundary, no-network contract, and platform packaging hooks.
- `check_ai10_writer_feasibility_sources.sh`: validates the AI-10 evaluation-only candidate, synthetic dataset, content-free No-Go evidence, no tracked weights/runtime artifacts, no arbitrary prompt CLI, and offline probe tests.
- `check_ai11_writer_integration_sources.sh`: validates the stronger AI-11 evaluation-only candidate, bounded/redacted Writer protocol, default-off resource policy, content-free Mac evidence, absent model approval, and fail-closed Helper response.
- `test_macos_ai_helper.sh`: compiles and runs the macOS controlled-child Helper lifecycle tests, including health, cancellation, crash recovery, and shutdown.
- `test_windows_ai_helper.ps1`: builds and runs the Windows current-user named-pipe Helper lifecycle probe on an x64 runner.

Planned scripts will be added with their owning AI stages.
