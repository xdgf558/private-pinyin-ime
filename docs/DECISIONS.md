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
Decision: Deliver each development stage through a GitHub pull request before merging to `main`.
Reason: The project owner wants to review and approve each stage before it enters the main branch.
Consequences: Codex should create a stage branch, commit scoped changes, push the branch, and open a pull request after each stage.

## Decision 003: Rust workspace layout

Date: 2026-07-06
Status: accepted
Decision: Use a root Cargo workspace with `ime_core` for the engine and `tools/test_cli` for the CLI package.
Reason: Keeping the core and CLI in one workspace allows shared validation commands, a committed `Cargo.lock`, and reproducible CLI and release builds.
Consequences: Stage 1 should create the root `Cargo.toml`, commit `Cargo.lock`, and validate the workspace with fmt, clippy, tests, and the CLI smoke test.
