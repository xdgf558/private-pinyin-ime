# Development Progress

Last updated: 2026-07-06 15:15
Current stage: stage-03
Current status: completed

## Stage Status

| Stage | Name | Status | Last checked | Notes |
|---|---|---|---|---|
| 01 | Rust core engine | completed | 2026-07-06 12:12 | Core engine, CLI, tests, and CI are ready for local review |
| 02 | User lexicon and prediction | completed | 2026-07-06 15:01 | Merged to `main` through PR #3 |
| 03 | C ABI and CLI integration | completed | 2026-07-06 15:15 | C ABI crate, header, C demo, ownership docs, and tests are ready for local review |
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
- Addressed stage-02 review feedback so idle Space commits a normal space while digit keys select prediction candidates.
- Reused one mutex-protected SQLite connection per user lexicon instance instead of reopening the database for each lookup or learning write.
- Recorded follow-up open items for SQLite prefix range queries, exact-match preservation before query limits, user/base ranking fusion, and sanitized DB error logging.
- Deduplicated compact pinyin normalization across base and user lexicon lookup.
- Merged stage 02 to `main` through GitHub PR #3.
- Implemented the stage-03 `ffi/ime_ffi` crate that exposes `libprivate_pinyin_ime`.
- Added `ffi/c_api.h`, output ownership rules, C demo, Swift/C++ integration notes, and C ABI CI coverage.
- Added FFI tests for engine/session creation, `nihao` input, candidate reading, commit output, null-handle behavior, and output freeing.

## Current Work

- Stage 03 is complete on local branch `codex/stage-03-c-abi`.
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
- Notes: 29 integration tests passed across parser, candidates, ranking, prediction, privacy logging, SQLite user lexicon behavior, and C ABI behavior.

- Command: `cargo run -p test_cli -- nihao`
- Result: passed
- Notes: Output includes `你好`.

- Command: `bash scripts/run_c_demo.sh`
- Result: passed
- Notes: C demo created an engine, fed `nihao`, read first candidate `你好`, and committed `你好`.

- Command: `leaks --atExit -- target/debug/ime_c_demo`
- Result: passed
- Notes: macOS `leaks` reported `0 leaks for 0 total leaked bytes`.

- Command: `git diff --check`
- Result: passed
- Notes: No whitespace errors.

## Open Items

- Select the final project license before external reuse or release.
- Replace sample lexicon data with licensed production lexicon data before release.
- Keep production runtime data outside source directories.
- Add indexed lexicon lookup before production dictionary scale.
- Refine Shift toggle semantics in platform hosts.
- Implement candidate paging in a later stage.
- Commit first candidate before punctuation during composition.
- Use range-prefix SQLite queries for indexed user lexicon prefix lookup.
- Preserve exact user lexicon matches before applying query limits.
- Fuse user and base ranking instead of unconditional user-first ordering.
- Wire sanitized user lexicon database failures into logging.

## Files Changed In Latest Stage

- `Cargo.lock`
- `README.md`
- `CHANGELOG.md`
- `.github/workflows/rust.yml`
- `docs/DEVELOPMENT_PROGRESS.md`
- `docs/DECISIONS.md`
- `ffi/`
- `scripts/run_c_demo.sh`
- `Cargo.toml`

## Next Step

- Review stage-03 locally; after approval, push and merge through GitHub.
