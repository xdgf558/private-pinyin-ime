# PrivatePinyin IME

PrivatePinyin IME is a privacy-first Chinese pinyin input method project targeting Windows, macOS, and iOS.

The project follows the staged development plan in `docs/private_pinyin_ime_development_spec.md`. The core architecture is a Rust input engine exposed through a C ABI, with thin platform hosts for Windows TSF, macOS InputMethodKit, and iOS Keyboard Extension.

## Privacy Defaults

- Local computation by default.
- No telemetry by default.
- No account system.
- No cloud sync.
- No clipboard access unless a future product spec explicitly adds an opt-in feature.
- Logs must not contain raw keys, pinyin input, candidates, committed text, or user context.
- Error logs must use structured error codes and must not embed the input string that caused the error.

## Current Status

Stage 13 is in local review: the Rust workspace, core engine crate, indexed production base lexicon, SQLite user lexicon range lookup, local bigram prediction, AOSP/pinyin-data lexicon import tooling, CLI smoke tools, C ABI crate, C demo, Windows TSF prototype with polished candidate popup positioning/DPI/theme handling, macOS InputMethodKit prototype with a preferences window, JSON settings loading, iOS container app and keyboard extension with App Group settings storage and learning opt-in, release packaging scripts, release distribution plan, App Store metadata templates, tests, Rust CI workflow, Windows Rust test and TSF compile CI wiring, platform smoke-test plan, core production-hardening checks, platform-host polish checks, settings/privacy checks, release-packaging checks, and lexicon scaffold checks are in place.

Public release is still gated on the final project license, owner-provided signing/provisioning credentials, notarization/App Store setup, and completed platform smoke-test records. The bundled base lexicon source/license/version gate is closed for the current AOSP+pinyin-data import.

## Development Workflow

All stage work should use this review flow:

1. Create a branch named `codex/<stage-or-task>`.
2. Implement only the current stage scope from the development spec.
3. Update progress, changelog, decisions, and open items as required.
4. Run the relevant validation commands.
5. Commit the completed stage locally and share the local review summary, diff scope, and validation results.
6. Fix review feedback on the same local branch until approved.
7. Push the approved branch to GitHub.
8. Merge to `main` only after approval, then sync local `main`.

## Rust Workspace

The root `Cargo.toml` defines a workspace with:

- `ime_core` is the core engine crate.
- `ffi/ime_ffi` exposes the C ABI as `libprivate_pinyin_ime`.
- `tools/test_cli` is a CLI package that depends on `ime_core`.
- `tools/settings_cli` manages settings snapshots and user lexicon clear/export actions for installer scripts.
- `tools/lexicon_builder` converts local lexicon source files into the project base-lexicon TSV format and writes an audit manifest.
- `Cargo.lock` must be committed to keep CLI and release builds reproducible.

Validation:

```bash
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo run -p test_cli -- nihao
cargo run -p private_pinyin_settings -- write-default --settings /tmp/private_pinyin_settings.json
cargo run -p private_pinyin_lexicon -- build-base --format private-pinyin-tsv --input ime_core/assets/base_lexicon_sample.tsv --output /tmp/private_pinyin_base.tsv --manifest /tmp/private_pinyin_lexicon_manifest.json --source-name "PrivatePinyin sample" --source-license "project-internal sample data"
bash scripts/run_c_demo.sh
bash scripts/check_windows_tsf_sources.sh
bash scripts/check_macos_imk_sources.sh
bash scripts/check_installers_settings_sources.sh
bash scripts/check_ios_keyboard_sources.sh
bash scripts/check_platform_validation_sources.sh
bash scripts/check_stage09_core_sources.sh
bash scripts/check_stage10_platform_host_sources.sh
bash scripts/check_stage11_settings_privacy_sources.sh
bash scripts/check_stage12_release_sources.sh
bash scripts/check_stage13_lexicon_sources.sh
bash scripts/build_macos_imk.sh
bash scripts/package_macos_pkg.sh
bash scripts/build_ios_keyboard.sh
```

## Next Stage

Next work should produce release-candidate evidence: choose the final project license, run Windows/macOS/iOS smoke records, and build signed/notarized/provisioned artifacts with owner credentials.
