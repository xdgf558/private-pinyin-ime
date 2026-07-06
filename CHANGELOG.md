# Changelog

## Unreleased

### Added

- Initialized the repository documentation and project skeleton.
- Added the development specification, progress tracker, decision log, and open item tracker.
- Added pull request workflow and privacy review checklist.
- Added the stage-01 Rust workspace with `ime_core` and `tools/test_cli`.
- Added `InputSession`, `KeyEvent`, `ImeOutput`, `Candidate`, basic pinyin parsing, embedded sample lexicon lookup, and simple candidate ranking.
- Added parser, candidate, ranking, prediction-placeholder, and privacy tests.
- Added minimal GitHub Actions for Rust formatting, clippy, and tests.
- Added input guardrails for maximum raw pinyin length, system-modifier passthrough, punctuation commits, and no-candidate space fallback.
- Added a guard so Enter without active raw input remains idle instead of committing an empty string.
- Added SQLite-backed user lexicon persistence for selected candidates.
- Added local bigram prediction after candidate commits.
- Added learning controls for `enable_user_learning` and `strict_privacy_mode`.
- Added tests for prediction, user lexicon persistence, disabled learning, and strict privacy mode.
- Added the stage-03 C ABI crate, public `ffi/c_api.h`, C demo, and Swift/C++ integration notes.
- Added FFI tests for engine/session creation, key input, candidate reading, commit output, null-handle behavior, and output freeing.
- Added CI coverage for building and running the C ABI demo.

### Changed

- Tightened initialization guidance for Rust lockfile handling, Xcode ignores, runtime data paths, Stage 1 workspace layout, and CI expectations.
- Updated README instructions for the Rust workspace and CLI smoke test.
- Updated the stage delivery workflow to use local review before GitHub push and merge.
- Changed candidate ordering to rank exact matches before prefix matches, then sort within each group by frequency.
- Merged user lexicon candidates ahead of base lexicon duplicates.
- Reused one SQLite connection per user lexicon instead of reopening the database on every lookup or learning write.
- Deduplicated compact pinyin normalization across base and user lexicon lookup.

### Fixed

- Fixed idle Space so prediction candidates no longer hijack normal space input.

### Security and Privacy

- Documented the default no-network, no-telemetry, no-account, no-cloud-sync privacy posture.
- Clarified that error logs must not embed user input, pinyin input, candidates, or committed text.
- Ensured strict privacy mode and disabled learning skip SQLite learning writes.
