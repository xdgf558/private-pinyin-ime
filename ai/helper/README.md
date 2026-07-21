# Desktop AI Helper

AI-09 introduces a dormant desktop process boundary for future optional Writer
features. It is not used by ordinary pinyin parsing, candidate generation, candidate
selection, learning, or AI Lite ranking.

The shared Rust helper uses a fixed, bounded binary protocol from
`ai/helper_protocol`:

- a 20-byte versioned header and payloads capped at 64 KiB;
- a random 32-byte authentication token for every process launch;
- at most eight active requests and 32 queued responses;
- health, cancellation, graceful shutdown, and a ten-minute idle exit;
- content-free error codes and redacted frame diagnostics;
- no network client, localhost service, content log, or persistent request cache.

On macOS the signed app launches its bundled helper as a controlled child and uses
anonymous pipes. On Windows the current-user host creates a random request/response
named-pipe pair with protected current-user-only DACLs and
`PIPE_REJECT_REMOTE_CLIENTS`, then launches the bundled helper with the authentication
token in its private child environment. Separate unidirectional pipes prevent a
synchronous read from blocking the helper's response writer.

Every failure means only that the optional enhancement is unavailable. Hosts must
never wait for this process from an IMK key-event callback or a TSF edit session.
AI-10 and AI-11 may add real work only through bounded background queues, complete
request identity, deadlines, cancellation, and the existing PrivacyGuard.

AI-11 adds a versioned Writer request/preview frame for short completion, explicit
rewrite, and explicit translation. Source text and suggestions are bounded, diagnostics
remain redacted, and request identity prevents stale output from being applied. This is
only a contract boundary: until an exact model passes every quality, platform, license,
and Owner gate, the helper validates Writer frames and returns `ModelUnavailable` without
running inference or echoing content.
