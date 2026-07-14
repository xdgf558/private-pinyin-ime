# AI-01 Baseline Report

Date: 2026-07-14

Revision basis: `main` at `6f71351` before local AI changes

Reference environment: macOS 26.5.2, arm64

Build mode for latency: `--release`

## Quality baseline

Command:

```bash
bash scripts/run_ai_eval.sh
```

Result:

| Metric | Baseline |
|---|---:|
| Required regressions | 13 / 13 passed |
| Observed AI opportunities | 0 / 7 met target |
| Overall Top-1 | 12 / 20 |
| Expected candidate found | 13 / 20 |
| Overall MRR | 0.625 |

All existing core, continuous-pinyin, shorthand-initial, and nine-key requirements
passed. The observed typo-correction, mixed-English, and mixed full-pinyin/initial cases
were not found, which is expected before AI-03 through AI-06.

## Reference latency

Command:

```bash
bash scripts/run_ai_eval.sh --benchmark --initialization-iterations 5 --lookup-iterations 100
```

| Feature | P50 | P95 | Maximum |
|---|---:|---:|---:|
| Engine initialization | 29.82 ms | 56.01 ms | 56.01 ms |
| Core candidate | 0.09 ms | 0.22 ms | 0.25 ms |
| Continuous pinyin | 0.90 ms | 1.48 ms | 1.51 ms |
| Nine-key | 0.17 ms | 3.67 ms | 3.74 ms |
| Pinyin correction opportunity | 0.04 ms | 0.09 ms | 0.10 ms |
| Mixed English opportunity | 0.04 ms | 0.25 ms | 0.27 ms |
| Mixed full-pinyin/initial opportunity | 0.01 ms | 0.01 ms | 0.01 ms |
| Shorthand initials | 0.01 ms | 0.02 ms | 0.03 ms |

These numbers are reference evidence, not portable thresholds. Windows, Intel macOS,
and real-device iOS latency and resident-memory baselines remain platform measurements
for AI-06 through AI-08. CI verifies deterministic quality instead of runner speed.

## Privacy statement

The dataset contains only repository regression cases and first-party synthetic cases.
No user lexicon, real typing, support message, application context, prompt, model output,
identifier, or telemetry was used.
