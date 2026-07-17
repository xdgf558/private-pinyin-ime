# Local AI Development Plan

Status: approved for staged implementation

Track: `AI-01` through `AI-12`

Principle: local enhancement must never become a dependency of basic input

## Product boundary

Local AI may improve candidate ordering, typo correction, mixed Chinese/English input,
short completion, explicit rewrite, translation, and user-lexicon cleanup suggestions.
It must not use cloud APIs, external local services, telemetry, clipboard content,
surrounding application documents, or persistent prompt/output logs.

The existing Rust parser, lexicon, continuous decoder, local bigram/trigram learning,
C ABI, and platform hosts remain authoritative. AI consumes bounded outputs from that
pipeline; it does not create a second learning database or replace the core.

## Implementation stages

| Stage | Scope | Exit condition |
|---|---|---|
| AI-01 | Offline evaluation corpus, quality runner, and report-only latency benchmark | Current required behavior is frozen; opportunity cases are measured; no runtime behavior changes |
| AI-02 | `local_ai_core` contracts, budgets, mock provider, request revision, and cancellation identity | Mock requests are deterministic and do not touch platform hosts |
| AI-03 | PrivacyGuard, secure-input signal, minimal context, sanitized errors, and no-network source gates | Sensitive and oversized requests are rejected without logging content |
| AI-04 | Rules-first pinyin correction, English-term preservation, and rule/statistics lexicon cleanup suggestions | P0 rules improve targeted cases without normal-input regression |
| AI-05 | Model manifest, SHA256/license gate, model packager, and hardware tiering | Unapproved or corrupt artifacts cannot load |
| AI-06 | Shared compact Rust AI Lite ranker using existing frequency, segmentation, bigram, trigram, typo, and term features | Targeted ranking improves within the 30 ms and memory budgets |
| AI-07 | macOS and Windows asynchronous integration with stale-result cancellation | Inference runs on bounded worker queues; visible numbered candidates never change identity after display; failures preserve input |
| AI-08 | iOS AI Lite integration for QWERTY and nine-key, with no Full Access requirement | Real-device memory and fallback checks pass; no heavy LLM is present |
| AI-09 | Signed desktop helper skeleton, authenticated local IPC, health, cancellation, and idle exit | Helper crashes and timeouts cannot affect basic input |
| AI-10 | Optional `llama.cpp` Writer feasibility spike with an owner-approved local model | License, Chinese quality, package size, startup, memory, and cancellation meet a go/no-go gate |
| AI-11 | Pause-triggered short completion followed by explicit rewrite and translation previews | Base candidates appear first; stale output is discarded; user confirms replacement |
| AI-12 | Cross-platform regression, privacy audit, fault injection, benchmarks, model notices, and release gates | AI-off behavior equals the pre-AI baseline and all failure modes degrade safely |

AI-04 implements deterministic rule components and offline evaluation only. Pinyin
correction is capped at two validated alternatives, English terms come from a small
first-party canonical table, and lexicon cleanup returns read-only reason-coded
suggestions. No platform host invokes these components before AI-07 supplies bounded
worker queues and stale-result handling.

AI-05 establishes a fail-closed supply-chain boundary without selecting a model. A
manifest self-assertion cannot authorize loading: exact artifact hashes, sizes, license,
privacy, runtime, platform, hardware policy, and a separately embedded Owner approval
fingerprint must agree. Paths and symbolic links are rejected, primary bytes are
reverified at use time, the approval registry starts empty, and no model weight is added.
AI-06 must use this gate for any compact scorer it proposes.

AI-02 keeps the runtime contract deliberately independent from `ime_core`, FFI, and
platform hosts. Its mock provider is a deterministic contract test, not an inference
implementation. AI-03 makes guarded construction the only public request path, rejects
sensitive and oversized content, retains no more than eight recent tokens, and adds
no-network/no-content-log source gates. Host-generated secure-input and revision signals
remain AI-07 work.

## Candidate stability rule

An asynchronous result must not reorder an already visible numbered candidate page.
AI-07 may either add a separately marked suggestion without shifting `1` through `9`,
or apply ranking to the next composition revision. A future provider may run before the
first display only after measurements prove that it is consistently fast enough.

Every request must carry an opaque session ID, composition revision, candidate-set hash,
secure-input flag, and deadline. Hosts discard results whose revision or candidate hash
does not match the current composition.

The candidate-set hash is a non-cryptographic lifecycle fingerprint. It must not become
a persistent or cross-process cache key; any such cache needs a separately versioned,
collision-resistant identity. `LocalAiProvider::infer` remains a synchronous provider
boundary, so AI-07 must dispatch it only through a bounded worker queue. A cooperative
deadline does not permit direct calls from IMK main-thread handling, TSF edit sessions,
or iOS input/UI callbacks.

## Evaluation method

Training and evaluation may use only owner-approved public data, repository regression
cases, and first-party synthetic examples. No user lexicon, support transcript, real app
context, telemetry, or private typing sample may enter a dataset.

AI Lite development compares Top-1, target-rank success, MRR, false-correction rate,
term-preservation rate, P50/P95/P99 latency, initialization time, and platform memory.
Latency thresholds are calibrated per hardware tier; shared CI validates deterministic
quality and source/privacy gates rather than machine-dependent timing.

## Review workflow

Each stage uses one `codex/ai-xx-*` branch and one focused PR. A stage updates the
changelog, progress record, decisions, open items, tests, and relevant source gates.
Model weights are never committed without owner approval of source, license, size, and
redistribution terms.
