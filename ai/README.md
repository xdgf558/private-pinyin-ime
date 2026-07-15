# Local AI Development

This directory contains the offline evaluation assets and, in later stages, the
local-only AI runtime for PrivatePinyin.

The local AI track follows these non-negotiable boundaries:

- Existing Rust candidate generation remains the immediate, authoritative input path.
- AI is optional, local-only, cancellable, and safe to disable or remove.
- No cloud API, external local model service, localhost HTTP server, account, or telemetry.
- No clipboard, surrounding document, email, webpage, or chat-history access.
- Raw input, candidates, prompts, outputs, and recent context must never enter logs.
- Model weights require owner approval, a redistribution-compatible license, and a manifest.
- iOS Keyboard Extension work is limited to lightweight inference.

AI-01 establishes evaluation and benchmark infrastructure. AI-02 adds the isolated
`local_ai_core` contract crate with deterministic mock behavior, bounded feature
budgets, deadlines, full session/revision/candidate identity, and identity-scoped
cancellation. Neither stage adds a model, host integration, settings entry, or
user-visible behavior.

Content-bearing request and response types expose redacted `Debug` output. The mock
provider is intentionally zero-dependency and is not connected to `ime_core`, the C
ABI, or any platform host. AI-03 owns privacy rejection and minimal-context policy;
AI-07 owns asynchronous host integration and stale-result disposal.

The approved implementation sequence is tracked in
[`docs/local_ai_development_plan.md`](../docs/local_ai_development_plan.md).
