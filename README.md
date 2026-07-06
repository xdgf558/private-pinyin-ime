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

Stage 9 is complete locally and awaiting review: the Rust workspace, core engine crate, indexed sample lexicon lookup, SQLite user lexicon range lookup, local bigram prediction, CLI smoke tools, C ABI crate, C demo, Windows TSF prototype, macOS InputMethodKit prototype, JSON settings loading, prototype installer packaging scripts, iOS container app and keyboard extension scaffold, tests, Rust CI workflow, Windows Rust test and TSF compile CI wiring, platform smoke-test plan, and core production-hardening checks are in place.

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
- `Cargo.lock` must be committed to keep CLI and release builds reproducible.

Validation:

```bash
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo run -p test_cli -- nihao
cargo run -p private_pinyin_settings -- write-default --settings /tmp/private_pinyin_settings.json
bash scripts/run_c_demo.sh
bash scripts/check_windows_tsf_sources.sh
bash scripts/check_macos_imk_sources.sh
bash scripts/check_installers_settings_sources.sh
bash scripts/check_ios_keyboard_sources.sh
bash scripts/check_platform_validation_sources.sh
bash scripts/check_stage09_core_sources.sh
bash scripts/build_macos_imk.sh
bash scripts/package_macos_pkg.sh
bash scripts/build_ios_keyboard.sh
```

## Next Stage

Stage 10 should polish platform-host experience, especially Windows candidate-window positioning/display attributes and macOS candidate/menu UI behavior in real applications.
