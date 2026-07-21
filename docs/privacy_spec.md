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
network transport, telemetry, persistent AI cache, or second learning database.

## Desktop AI Helper Boundary

AI-09 packages a dormant, separately signed desktop helper for future optional Writer
features. It is not used by ordinary input or AI Lite ranking. Every launch uses a new
random 32-byte authentication token; unauthenticated, malformed, oversized, or
version-mismatched frames fail closed. Frames are capped at 64 KiB, active work and
response queues are bounded, diagnostics redact payloads, and only content-free error
codes may be emitted.

macOS may communicate only with the helper process it launched through anonymous child
pipes. Windows may communicate only through a random unidirectional request/response
named-pipe pair protected by current-user-only DACLs with remote clients rejected.
Neither transport is a network or localhost service. The helper must not access cloud APIs, telemetry, clipboard,
surrounding documents, persistent request/output caches, or content logs, and exits
after ten minutes without activity.

Helper absence, failed authentication, queue saturation, cancellation, timeout, crash,
or restart must affect only the optional enhancement. IMK key callbacks and TSF edit
sessions must never wait for helper work. Future AI-10/AI-11 payloads still require the
same `PrivacyGuard`, explicit action policy, bounded context, deadline, complete request
identity, stale-result rejection, and user confirmation rules established above.

## AI-10 Writer Feasibility

AI-10 is an offline development probe, not a product input path. It accepts only the
checked-in first-party synthetic dataset and an exact locally supplied model/runtime pair;
the CLI has no arbitrary-prompt option and no network client. It must never process user
typing, clipboard data, surrounding documents, webpages, messages, or imported lexicon
content. Model weights and llama.cpp binaries are not stored in this repository or app.
The probe may pass only those checked-in synthetic prompts to the external evaluation
runtime through process arguments. This exception is limited to the offline AI-10 tool.
Production AI-11 Writer request and output content must use the authenticated AI-09 Helper
protocol and must never appear in process arguments, environment variables, temporary
files, diagnostics, or persistent caches.

Quality checks operate in memory. The persisted report contains only candidate identity,
platform, timings, peak RSS, output length, result codes, cancellation timing, and the
Go/No-Go decision. It contains no prompts, generated text, artifact paths, or user data.
The evaluated candidate remains unapproved and may not be registered, packaged, loaded by
the AI-09 Helper, or used by a platform host. Any future Writer integration must keep the
same no-network/content-log rules and add `PrivacyGuard`, explicit user action, bounded
background execution, cancellation, complete request identity, and stale-result rejection.

## AI-11 Gated Writer Contracts

AI-11 defines the bounded Writer wire contract and evaluates a stronger exact candidate,
but it does not enable a product Writer path. Writer remains unavailable until every model and platform gate passes. In particular, no Writer UI, platform-host request path, model
registration, model bundle, or installer payload is enabled by this stage.

Production Writer source and result content may cross only the authenticated AI-09 Helper
channel. It must never appear in process arguments, environment variables, temporary
files, diagnostics, telemetry, persistent caches, or command history. A request is capped
at 4,096 UTF-8 bytes and 600 characters, may return at most three equally bounded preview
suggestions, and carries a deadline no longer than three seconds plus opaque session,
request, revision, and source identities. Late, cancelled, mismatched, malformed, or
oversized results are discarded without changing the user's text.

Pause-triggered short completion may be considered only after the release gates pass.
Rewrite and translation always require an explicit user action, and every replacement
remains a preview until the user confirms it. The dormant helper currently validates the
Writer request and then returns only the content-free `ModelUnavailable` error. It does
not infer, persist, log, or echo the source text.

## iOS AI Host Integration

AI-08 links only the isolated `ios-ai` feature and the same approved fixed-point Lite
ranker used by the desktop hosts. It does not request Full Access, add a network API,
read clipboard or surrounding document content, persist AI requests or responses, or
create a second learning store. The Keyboard Extension remains `RequestsOpenAccess=false`.

The extension checks current process-available memory before optional AI initialization
and then applies the AI-05 physical-memory policy. iOS replaces third-party keyboards in
secure text fields; numeric and phone input traits additionally fail closed and cancel
optional AI work. A rejected model, unsupported hardware, low available memory, secure
or numeric context, full queue, cancelled request, expired deadline, stale revision,
mismatched candidate identity, or invalid permutation leaves ordinary input and the base
candidate order unchanged. Provider inference runs only on the bounded worker and never
inside a keyboard input/UI callback.

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
