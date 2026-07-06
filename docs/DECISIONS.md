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
