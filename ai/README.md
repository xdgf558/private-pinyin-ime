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
ABI, or any platform host. AI-03 adds the only public request-construction path through
`AiRequestBuilder` and `PrivacyGuard`; AI-07 owns asynchronous host integration and
stale-result disposal.

`AiCandidateSetHash` is a non-cryptographic request-lifecycle fingerprint, not a
persistent or cross-process cache key. Although `LocalAiProvider::infer` is synchronous
at the provider boundary, AI-07 hosts must call it only from a bounded worker queue;
deadlines do not make direct calls from an IMK, TSF, or iOS input thread safe.

AI-03 rejects secure-input, sensitive, oversized, disabled, unlicensed-model, unsupported
hardware, expanded-budget, and implicit rewrite/translation requests before inference.
It retains at most the last eight non-empty session tokens and structurally excludes the
clipboard, surrounding application documents, webpages, email, chat history, and screen
content. Source gates prohibit network clients, external AI services, and runtime content
logging. No model, FFI, host integration, setting, or visible behavior is added.

AI-04 adds bounded deterministic correction, canonical English-term preservation, and
read-only cleanup suggestions. AI-05 adds the model supply-chain boundary: strict JSON
manifests, external Owner approval fingerprints, streaming SHA-256 and size checks,
relative-path and symlink rejection, privacy/platform/hardware gates, and an atomic local
packager. The embedded approval registry is empty, so no model can load after AI-05.
No model weight, inference provider, FFI change, host integration, setting, or visible
input behavior is included. See
[`model_package_policy.md`](model_package_policy.md) before evaluating any artifact.

The approved implementation sequence is tracked in
[`docs/local_ai_development_plan.md`](../docs/local_ai_development_plan.md).
