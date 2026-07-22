# Desktop AI Helper

AI-09 introduced a dormant desktop process boundary for optional Writer features.
Decision 043 activates that boundary for explicit desktop rewrite and translation, while
ordinary pinyin parsing, candidate generation, candidate selection, learning, and AI Lite
ranking remain independent from it.

The shared Rust helper uses a fixed, bounded binary protocol from
`ai/helper_protocol`:

- a 20-byte versioned header and payloads capped at 64 KiB;
- a random 32-byte authentication token for every process launch;
- at most eight active requests and 32 queued responses;
- health, cancellation, graceful shutdown, and a ten-minute idle exit;
- content-free error codes and redacted frame diagnostics;
- no external network client, content log, or persistent request cache.

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
remain redacted, and request identity prevents stale output from being applied. In the
historical AI-11 profile the helper returned only `ModelUnavailable`.

The post-AI-12 Writer V1 verifies the exact on-demand model and starts the bundled pinned
`llama-server` as its own child. The server binds only to `127.0.0.1` on an ephemeral port,
requires a random API key, and starts with `--offline`, `--no-webui`, and `--log-disable`.
This loopback connection is an implementation detail inside the authenticated Helper
boundary, not an externally reachable service. Hosts own the fixed official model download;
the Helper contains no external URL or downloader. Source and generated text never enter
argv, logs, telemetry, temporary prompt files, or persistent caches. Strict privacy,
cancelled or stale work, runtime/model failure, and timeout return only sanitized errors.
