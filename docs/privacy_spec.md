# Privacy Specification

PrivatePinyin IME is privacy-first by default.

## Defaults

- No network access by default.
- No telemetry SDK.
- No account system.
- No cloud sync.
- No clipboard reads.
- No full sentence persistence.

## Forbidden Log Content

Logs must not include:

- Raw key input.
- Pinyin input.
- Candidate text.
- Committed text.
- User context.
- User lexicon entries.

## Allowed Log Content

Logs may include:

- Module startup and shutdown events.
- Version numbers.
- Error codes.
- Timing measurements.
- Non-content diagnostic state.

## Error Reporting

Error logs must use structured error codes or enum variants. They must not include the input string, pinyin text, candidate text, committed text, or user context that caused the error.

Rust code should avoid `unwrap`, `expect`, and debug-format panic messages on paths that can include user input. Errors crossing API or FFI boundaries should be sanitized before logging or returning them to platform hosts.

## Strict Privacy Mode

When strict privacy mode is enabled, the engine must not write new learning data, user lexicon updates, or contextual statistics.

## User Lexicon Storage

The user lexicon may store selected phrase text, pinyin, compact pinyin, frequency, update time, one-step selected-phrase transitions, and bounded short phrase completions derived only from selected candidates. It must not store complete sentences, raw key streams, surrounding document text, clipboard content, or account identifiers.

When `enable_user_learning` is disabled or strict privacy mode is enabled, candidate commits must not create or update user lexicon rows.
