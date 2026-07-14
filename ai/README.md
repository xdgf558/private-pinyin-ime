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

AI-01 establishes evaluation and benchmark infrastructure only. It does not add a
model, provider, host integration, settings entry, or user-visible behavior.

The approved implementation sequence is tracked in
[`docs/local_ai_development_plan.md`](../docs/local_ai_development_plan.md).
