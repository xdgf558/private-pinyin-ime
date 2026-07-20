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
anonymous pipes. On Windows the current-user host creates a random named pipe with a
protected current-user-only DACL and `PIPE_REJECT_REMOTE_CLIENTS`, then launches the
bundled helper with the authentication token in its private child environment.

Every failure means only that the optional enhancement is unavailable. Hosts must
never wait for this process from an IMK key-event callback or a TSF edit session.
AI-10 and AI-11 may add real work only through bounded background queues, complete
request identity, deadlines, cancellation, and the existing PrivacyGuard.
