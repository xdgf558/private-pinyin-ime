# Development Progress

Last updated: 2026-07-06 12:12
Current stage: stage-01
Current status: completed

## Stage Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| 01 | Rust core engine | completed | 2026-07-06 12:12 | Core engine, CLI, tests, and CI are ready for local review |
| 02 | User lexicon and prediction | not_started | | Depends on stage 01 |
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

## Current Work

- Stage 01 is complete on local branch `codex/stage-01-core-engine`.
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
- Notes: 19 integration tests passed across parser, candidates, ranking, prediction placeholder, and privacy logging.

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

## Files Changed In Latest Stage

- `.github/workflows/rust.yml`
- `README.md`
- `CHANGELOG.md`
- `Cargo.toml`
- `Cargo.lock`
- `docs/DEVELOPMENT_PROGRESS.md`
- `docs/DECISIONS.md`
- `docs/OPEN_ITEMS.md`
- `ime_core/Cargo.toml`
- `ime_core/README.md`
- `ime_core/src/`
- `ime_core/tests/`
- `tools/README.md`
- `tools/test_cli/`

## Next Step

- Review stage-01 locally; after approval, push and merge through GitHub.
