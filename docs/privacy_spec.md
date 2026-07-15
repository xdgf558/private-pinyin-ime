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

## Update Checks

The macOS host may check a fixed first-party HTTPS release manifest only after
the user explicitly enables automatic checks or starts a manual check. Automatic
checks are off by default and run at most once every 24 hours. Strict privacy
mode pauses automatic checks and requires confirmation before a manual check.

The update request must not include raw keys, pinyin, candidates, committed
text, document context, user-learning records, account identifiers, telemetry,
or a persistent tracking cookie. The shared Rust engine must remain network-free.
Update failures must be shown through sanitized state and must never interrupt
typing.

## Update Package Downloads

The macOS host may download a package only after the user explicitly selects
`下载并验证` for a validated newer version. Automatic checks must never start a
package transfer. Enabling strict privacy mode cancels an active transfer.

The package request is restricted to the same fixed first-party HTTPS host and
must not include input content, user-learning data, document context, account
identifiers, telemetry, cookies, or a referrer derived from user activity. The
download is kept in a private local cache and is deleted if its size, SHA-256,
Developer ID Installer identity, or Apple notarization check fails.

Application-controlled verification operates on the local package through
fixed macOS system tools. Gatekeeper may consult Apple security services under
the system's own policy; the app provides no input content, learning data,
account identifier, or telemetry. The host must use fixed structured failure
states rather than include command output, local paths, certificate details, or
other environment data in user-facing errors or logs. Opening macOS Installer
requires a second visible user confirmation; the app must never silently invoke
a privileged installer or provide credentials.

## Post-Install Process Refresh

After a macOS package install, the UI-only refresh helper may inspect only the
bundle identifier, PID, and launch date of running 猫栈拼音 application
instances. It must exclude its own PID, must not inspect document content or
other applications' process details, and must not upload or log the detected
values.

The helper may request a normal exit only for a still-running PID that belongs
to the exact 猫栈拼音 bundle identifier, was detected as older than the install,
and is revalidated immediately after explicit user confirmation. It must never
force-terminate a process, close unrelated applications, automatically log the
user out, or restart the computer. Logout/login guidance is permitted only when
the old input-method process does not exit normally.

## User Lexicon Storage

The user lexicon may store selected phrase text, pinyin, compact pinyin, frequency, update time, one-step selected-phrase transitions, bounded short phrase completions, and three-token transition records derived only from selected candidates. A trigram record contains two selected context tokens plus the selected next token and its pinyin; it must not include surrounding document text or an unbounded sentence.

Learned ranking weight uses a 30-day inactivity half-life. Local storage is bounded to 20,000 selected phrases, 20,000 bigrams, 10,000 short phrase completions, and 20,000 trigrams by default. Capacity maintenance removes the lowest decayed-weight and oldest rows first. The in-memory session retains at most the eight most recent selected tokens.

User learning data remains in the platform-local SQLite file. It must not be uploaded, synchronized, or sent to a network service by the core engine.

When `enable_user_learning` is disabled or strict privacy mode is enabled, candidate commits must not create or update user lexicon rows.
