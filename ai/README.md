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
persistent or cross-process cache key. `LocalAiProvider::infer` remains synchronous at
the provider boundary. AI-07 dispatches it through `BoundedAiWorker` for macOS and
Windows; deadlines do not make direct calls from an IMK, TSF, or iOS input thread safe.

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
packager.

AI-06 adds the first approved package: a 426-byte first-party fixed-point coefficient
table for `AiLiteRanker`. It scores only structured `0..1000` frequency, segmentation,
bigram, trigram, typo-correction, and term-preservation signals plus bounded base-order
priors. The model contains no user data, performs no network access, stores no input,
keeps stable ties in base order, and returns reason-coded candidate references.

AI-07 embeds and re-verifies that approved package in the optional `desktop-ai` FFI
feature. macOS and Windows submit guarded candidate snapshots to a bounded worker,
cancel stale work by complete identity, and never block their input/edit threads.
Platform secure-input signals cancel or suppress inference, while every unavailable,
rejected, late, or saturated path leaves ordinary candidates untouched. iOS does not
link this feature and remains AI-off until AI-08. See
[`model_package_policy.md`](model_package_policy.md) before evaluating any artifact.

AI-09 adds the dormant desktop Helper boundary used by future Writer experiments.
The helper is a separately signed executable with a bounded binary protocol,
per-launch authentication, health checks, cancellation, crash recovery, and a
ten-minute idle exit. macOS uses controlled-child anonymous pipes; Windows uses a
random current-user-only named pipe that rejects remote clients. It is not connected
to basic input or the AI Lite candidate path. See [`helper/README.md`](helper/README.md).

AI-10 adds an offline feasibility probe for one exact Qwen2.5 0.5B Q4_K_M candidate
and official llama.cpp runtime. Only metadata, first-party synthetic cases, and a
content-free Mac report are checked in; weights and runtime binaries remain external.
The candidate passed two of three quality cases, so Decision 040 records `NoGo` and the
model is not approved, bundled, loaded by the Helper, or connected to typing. See
[`writer_feasibility/QWEN_MODEL_NOTICE.md`](writer_feasibility/QWEN_MODEL_NOTICE.md).

The approved implementation sequence is tracked in
[`docs/local_ai_development_plan.md`](../docs/local_ai_development_plan.md).
