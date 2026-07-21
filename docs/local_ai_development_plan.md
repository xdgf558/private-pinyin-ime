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
| AI-10 | Optional `llama.cpp` Writer feasibility spike with one exact evaluation-only model | Source, license, hashes, Chinese quality, package size, startup, memory, cancellation, and an explicit go/no-go decision are recorded; only a Go candidate may continue |
| AI-11 | Pause-triggered short completion followed by explicit rewrite and translation previews | Base candidates appear first; stale output is discarded; user confirms replacement |
| AI-12 | Cross-platform regression, privacy audit, fault injection, benchmarks, model notices, and release gates | AI-off behavior equals the pre-AI baseline and all failure modes degrade safely |

AI-04 implements deterministic rule components and offline evaluation only. Pinyin
correction is capped at two validated alternatives, English terms come from a small
first-party canonical table, and lexicon cleanup returns read-only reason-coded
suggestions. No platform host invokes these components before AI-07 supplies bounded
worker queues and stale-result handling.

AI-05 establishes a fail-closed supply-chain boundary before selecting a model. A
manifest self-assertion cannot authorize loading: exact artifact hashes, sizes, license,
privacy, runtime, platform, hardware policy, and a separately embedded Owner approval
fingerprint must agree. Paths and symbolic links are rejected and primary bytes are
reverified at use time.

AI-06 uses that boundary for a shared fixed-point Rust ranker. The approved first-party
package is a 426-byte coefficient table over bounded base-order, frequency, segmentation,
bigram, trigram, typo-correction, and English-term signals. Its 12-case synthetic and
project-regression gate improves eight targeted ranks, preserves four base winners, and
keeps all inference scratch state bounded.

AI-07 connects that ranker to macOS and Windows only. The C ABI owns a bounded,
non-blocking worker queue and complete request identity; host key/edit callbacks never
call synchronous inference. macOS contributes the system secure-event-input signal,
Windows contributes TSF password input-scope classification, and both contribute current
physical-memory policy. A late, cancelled, mismatched, secure-field, unsupported-hardware,
or unavailable-model result is ignored while the ordinary core candidates continue.
The approved package is embedded in desktop FFI builds and is rechecked through the full
AI-05 approval, platform, hardware, size, and SHA-256 gates before use.

AI-08 reuses that runtime in iOS rather than adding a second inference path. The keyboard
links only the isolated `ios-ai` feature and approved 426-byte fixed-point coefficients;
it does not link the desktop host feature, request Full Access, use network APIs, inspect
surrounding document context, or add persistent AI state. Engine creation first checks
current process-available memory, then the AI-05 physical-memory policy. Numeric and phone
input traits fail closed for optional AI work, while iOS itself replaces third-party
keyboards in secure text fields. Queue saturation, stale identity, deadline expiry,
unsupported hardware, memory pressure, or any initialization failure leaves the ordinary
keyboard and candidate order unchanged. Simulator builds and deterministic fallback tests
are automated; real-device latency, resident memory, memory-pressure behavior, and secure
field replacement remain the stage release gate before lowering the approved 8-GiB policy.

AI-09 establishes the desktop process boundary before any heavy Writer feasibility work.
The shared Rust helper speaks a fixed binary protocol with a 64-KiB payload ceiling,
per-launch 256-bit authentication, bounded active work and response queues, health,
cancellation, graceful shutdown, content-free diagnostics, and a ten-minute idle exit.
macOS launches a separately signed bundled helper through anonymous child pipes. Windows
uses a random unidirectional request/response named-pipe pair protected by
current-user-only DACLs and remote-client rejection.
Lifecycle probes exercise authentication, cancellation, forced helper termination,
restart, and clean shutdown. The helper is deliberately dormant: ordinary typing and AI
Lite ranking never depend on it, and AI-10/AI-11 must keep every real request off IMK and
TSF input threads behind PrivacyGuard, deadlines, and stale-result rejection.

AI-10 evaluates, but does not approve or ship, the exact Apache-2.0
`Qwen2.5-0.5B-Instruct-GGUF` Q4_K_M artifact at revision
`9217f5db79a29953eb74d5343926648285ec7e67` with official llama.cpp release `b10069`.
The repository contains only pinned candidate metadata, first-party synthetic cases, an
offline bounded probe, and a content-free Mac result. Model weights and runtime binaries
remain outside the repository and product. The measured candidate used about 579 MiB
peak RSS and produced its first byte in 276-295 ms, while cancellation completed within
the 500-ms budget. Each case launches a fresh runtime, so this first-byte measurement
includes process startup and cold model loading rather than warmed inference alone. It
passed two of three Chinese quality cases but failed the polite
rewrite requirement, so the recorded release decision is `NoGo`. AI-11 must not enable
Writer payloads with this candidate. A stronger candidate needs a new exact manifest,
provenance review, synthetic evaluation, explicit Owner approval, native Windows RSS
evidence, and separate cold-start and warmed-request latency evidence. The AI-10 tool's
synthetic prompt argv is evaluation-only; production Writer content must cross only the
authenticated AI-09 Helper protocol and must never be placed in a process command line.

AI-11 adds that production protocol boundary without activating the feature. Writer
requests and previews are versioned, size-bounded, deadline-bounded, identity-scoped,
and content-redacted in diagnostics. Short completion is reserved for a future
pause-triggered flow. Its future default-off UI must explicitly say “停顿时当前输入会交给本地 AI 进程”,
and model installation alone never counts as consent. Rewrite and translation always
require an explicit user action, and every replacement remains a preview until confirmation.
Strict privacy force-disables all three Writer modes while leaving stateless AI Lite
reranking under its separate policy. The helper currently returns only `ModelUnavailable`,
so no host can accidentally invoke an unapproved model.

The exact Apache-2.0 Qwen2.5 1.5B Instruct Q4_K_M evaluation candidate at revision
`dd26da440ef0330c47919d1ecae0966d24022222` passed all five first-party Mac cases with
321-444 ms cold-process first-byte latency, immediate cancellation, and about 1,192 MiB
peak RSS. This is a technical Mac pass, not a release approval. The model remains outside
the repository, approval registry, applications, installers, and helper until warmed
latency, native Windows memory, final packaging, and explicit Owner redistribution gates
also pass.

AI-02 keeps the runtime contract deliberately independent from `ime_core`, FFI, and
platform hosts. Its mock provider is a deterministic contract test, not an inference
implementation. AI-03 makes guarded construction the only public request path, rejects
sensitive and oversized content, retains no more than eight recent tokens, and adds
no-network/no-content-log source gates. AI-07 supplies desktop secure-input and revision
signals without changing the request contract.

## Candidate stability rule

An asynchronous result must not reorder an already visible numbered candidate page.
AI-07 applies a ready result before first display when available without waiting, or to
the next compatible composition revision. It never shifts `1` through `9` after that
page has become visible. A future provider may use a different presentation only after
its candidate identity and interaction semantics receive separate review.

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
