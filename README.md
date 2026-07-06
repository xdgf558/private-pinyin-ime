# PrivatePinyin IME

PrivatePinyin IME is a privacy-first Chinese pinyin input method project targeting Windows, macOS, and later iOS.

The project follows the staged development plan in `docs/private_pinyin_ime_development_spec.md`. The core architecture is a Rust input engine exposed through a C ABI, with thin platform hosts for Windows TSF, macOS InputMethodKit, and iOS Keyboard Extension.

## Privacy Defaults

- Local computation by default.
- No telemetry by default.
- No account system.
- No cloud sync.
- No clipboard access unless a future product spec explicitly adds an opt-in feature.
- Logs must not contain raw keys, pinyin input, candidates, committed text, or user context.

## Current Status

Project initialization is complete. Stage 1, the Rust core engine, has not started yet.

## Development Workflow

All stage work should use this review flow:

1. Create a branch named `codex/<stage-or-task>`.
2. Implement only the current stage scope from the development spec.
3. Update progress, changelog, decisions, and open items as required.
4. Run the relevant validation commands.
5. Push the branch and open a pull request.
6. Wait for human review and approval before merging.

## Next Stage

Stage 1 will create the Rust core engine and CLI test tool.

Expected validation for Stage 1:

```bash
cargo test
cargo run --bin test_cli
```
