# AI-06 Lite Ranker Evaluation

Date: 2026-07-18

Model: `private-pinyin.ai-lite-ranker` `1.0.1`

Approval fingerprint: `8bc7977a88f64a818fd232b7cfafd19af477232259e700d690ea37dfa639d439`

## Artifact And Data

- Fixed-point coefficient artifact: 426 bytes, ranker version `ai06-v1`, feature schema version `1`.
- License/provenance notice: 614 bytes.
- Runtime: shared Rust `rust_compact`; no GPU, network, service, telemetry, or input storage.
- Inputs: bounded `0..1000` frequency, segmentation, bigram, trigram,
  typo-correction, and term-preservation signals plus base-order priors.
- Evaluation: 12 first-party synthetic/project-regression cases; no user data, real
  application context, prompts, or model outputs.

## Quality

| Metric | Baseline | AI Lite ranker |
|---|---:|---:|
| Top-1 | 4 / 12 | 12 / 12 |
| MRR | 0.653 | 1.000 |
| Targeted improvements | - | 8 / 8 |
| Preservation cases | - | 4 / 4 |
| Regressions | - | 0 |

## Budget Evidence

The ranker caps one request at 32 candidates and three returned suggestions, limits its
model JSON to 64 KiB, and retains at most 256 cancelled request identities. A unit test
runs the maximum 32-candidate request under the existing 30 ms contract. A local arm64
macOS reference run observed 5 microseconds maximum and 2.1 microseconds mean inference
across the 12-case dataset. These timings are reference-only, not portable shared-runner
thresholds; `AI-OI-001` remains open for Windows, Intel macOS, and real-device iOS memory
and latency calibration before host integration.

## Boundary

AI-06 does not connect the ranker to `ime_core`, the C ABI, macOS, Windows, or iOS.
AI-07 must provide bounded worker queues, trustworthy secure-input and composition
revision signals, stale-result cancellation, and visible candidate stability before any
user-facing ranking change.
