# Privacy Specification

PrivatePinyin IME is privacy-first by default.

## Defaults

- No network access by default.
- No telemetry SDK.
- No account system.
- No cloud sync.
- No clipboard reads.
- No full sentence persistence.

## Optional iOS Lexicon Download

The iOS container App may download a reviewed optional dictionary subset only after the
user taps the dedicated import action and confirms the source and GPL license. This is
not a keyboard request: the Keyboard Extension remains `RequestsOpenAccess=false` and
contains no network API.

The request uses fixed HTTPS URLs for `rime-ice` release `2026.03.26`, an ephemeral
session, exact byte counts, and pinned SHA-256 values. It contains no raw keys, pinyin,
candidates, committed text, document context, learning data, account identifier,
telemetry, cookies, or user-derived query parameters. Temporary files are deleted after
verification/import, and no download starts automatically or in the background.

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

## Local AI Requests

Every local AI request must be constructed through `AiRequestBuilder` and accepted by
`PrivacyGuard` before it can reach a provider. The guard rejects secure-input fields,
password/secret assignments, one-time codes, payment-card numbers, Chinese identity
numbers, phone numbers, oversized text/context, disabled features, unapproved model
licenses, unsupported hardware, expanded budgets, and rewrite/translation requests that
were not explicitly initiated by the user.

An accepted request may contain only current raw pinyin, current composition text, the
current bounded candidate page, at most the eight most recent non-empty selected tokens,
and an explicitly requested draft. It has no fields for clipboard data, surrounding
documents, webpages, email bodies, chat history, screenshots, or other application
content. Sensitive-pattern rejection supplements platform secure-input signals; it does
not replace the AI-07 requirement for trustworthy host field classification. A request
must also declare whether raw input is full pinyin or nine-key digits, so numeric
one-time-code rejection cannot silently disable ordinary nine-key composition.

Local AI runtime sources must not use HTTP, WebSocket, gRPC, localhost model services, or
cloud AI APIs. They must not emit request, candidate, prompt, output, or recent-context
content through logging macros. Privacy failures expose only stable `AiErrorCode` values.

Rules-first pinyin correction and canonical English-term matching are stateless and may
be allowed in strict privacy mode because they do not read or write learning data.
User-lexicon cleanup is different: it inspects a bounded local snapshot and therefore
must be disabled in strict privacy mode. Cleanup returns only reason-coded suggestions;
it never deletes a record automatically.

## Local AI Model Packages

A model manifest is not authority by itself. Loading requires a redistribution-compatible
license assertion, an exact independently embedded Owner approval fingerprint, the
declared target platform, sufficient hardware, and successful size/SHA-256 verification
of every artifact. A registry entry may be added only after the model source, exact
revision, license, notice, quality evidence, size, and redistribution terms receive
explicit Owner review. The current AI-06 entry authorizes only the first-party 426-byte
fixed-point candidate-ranker coefficients; it does not authorize other weights.

Model package paths must remain inside one package root and must not use symbolic links.
The privacy declaration must require local execution, no network service, and no storage
of input content. Integrity, approval, platform, and hardware failures return only stable
error codes; they must not expose artifact paths, model bytes, or machine details. A
verified primary model is hashed again as it is read so replacement after initial package
verification cannot enter inference unnoticed.

AI-06 ranker inputs are bounded numeric signals derived from the current candidate page
and existing local engine state. The ranker does not create a learning database, retain a
request, send data over a network, or log candidate content. Its checked-in evaluation
dataset contains only first-party synthetic/project-regression cases and explicitly
declares that it contains no user data or real application context.

## Desktop AI Host Integration

AI-07 enables the approved AI Lite ranker only in macOS and Windows desktop FFI builds.
Synchronous provider inference runs exclusively on a bounded worker thread. IMK key
handling and TSF edit sessions may submit or poll work but must never wait for it. Queue
saturation, worker failure, cancellation, deadline expiry, model rejection, or hardware
rejection must preserve ordinary input and candidates.

Each desktop request is scoped to an opaque session ID, monotonic composition revision,
request ID, lifecycle-only candidate hash, exact candidate snapshot, secure-input state,
and deadline. Results that do not still match every relevant field are discarded. Once a
numbered candidate page is visible, asynchronous completion must not change the identity
of its entries.

macOS uses the system secure-event-input signal and Windows uses the TSF password input
scope. Windows treats an unavailable or failed input-scope probe as secure instead of
allowing AI work to fail open. Entering a secure field cancels outstanding AI work and
prevents new requests.
These platform signals supplement the shared `PrivacyGuard`; neither host may inspect or
send surrounding document content. The desktop integration has no request-content log,
network transport, telemetry, persistent AI cache, or second learning database. iOS does
not link the desktop AI feature and remains unchanged until AI-08.

Strict privacy mode still permits the AI-07 candidate ranker because it is stateless,
local-only, bounded to the current candidate page, and writes no learning or AI cache.
Strict privacy continues to disable user-learning and contextual-statistics writes.

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
