# Development Progress

Last updated: 2026-07-06 14:11
Current stage: stage-02
Current status: completed

## Stage Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| 01 | Rust core engine | completed | 2026-07-06 12:12 | Core engine, CLI, tests, and CI are ready for local review |
| 02 | User lexicon and prediction | completed | 2026-07-06 14:11 | SQLite user lexicon, learning controls, and local prediction are ready for local review |
| 03 | C ABI and CLI integration | not_started | | Depends on stage 01 and stage 02 |
| 04 | Windows TSF prototype | not_started | | Depends on stable C ABI |
| 05 | macOS InputMethodKit prototype | not_started | | Depends on stable C ABI |
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

## Current Work

- Stage 02 is complete on local branch `codex/stage-02-user-lexicon-prediction`.
- Awaiting local review before pushing to GitHub.

## Validation Results

- Command: `cargo fmt --check`
- Result: passed
- Notes: Formatting is clean.

- Command: `cargo clippy --workspace --all-targets -- -D warnings`
- Result: passed
- Notes: No clippy warnings.

- Command: `cargo test --workspace`
- Result: passed
- Notes: 26 integration tests passed across parser, candidates, ranking, prediction, privacy logging, and SQLite user lexicon behavior.

- Command: `cargo run -p test_cli -- nihao`
- Result: passed
- Notes: Output includes `你好`.

## Open Items

- Select the final project license before external reuse or release.
- Replace sample lexicon data with licensed production lexicon data before release.
- Keep production runtime data outside source directories.
- Add indexed lexicon lookup before production dictionary scale.
- Refine Shift toggle semantics in platform hosts.
- Implement candidate paging in a later stage.
- Commit first candidate before punctuation during composition.

## Files Changed In Latest Stage

- `Cargo.lock`
- `README.md`
- `CHANGELOG.md`
- `docs/DEVELOPMENT_PROGRESS.md`
- `docs/DECISIONS.md`
- `docs/OPEN_ITEMS.md`
- `ime_core/Cargo.toml`
- `ime_core/src/`
- `ime_core/tests/`

## Next Step

- Review stage-02 locally; after approval, push and merge through GitHub.
