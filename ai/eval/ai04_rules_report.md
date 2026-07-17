# AI-04 Rules-First Report

Date: 2026-07-17

Mode: deterministic offline rules; no model and no production host integration

## Quality

Command:

```bash
bash scripts/run_ai_eval.sh --rules --require-observed-successes 7
```

Result:

| Metric | AI-04 rules |
|---|---:|
| Required regressions | 13 / 13 passed |
| Observed opportunities | 7 / 7 met target |
| Overall Top-1 | 19 / 20 |
| Expected candidate found | 20 / 20 |
| Overall MRR | 0.975 |
| Pinyin correction target | 3 / 3 |
| Mixed-English target | 3 / 3 |

The remaining non-Top-1 case is the existing nine-key dinner sentence, which remains
inside its required target rank. Rules mode does not alter required core, continuous,
shorthand, or nine-key evaluation behavior.

## Safety Boundary

- Pinyin correction returns at most two validated alternatives and never removes the
  original input path.
- The first-party English term table preserves canonical spelling such as `Codex`,
  `GitHub`, `PR`, and `API key` without a network request.
- Lexicon cleanup only analyzes an explicit bounded snapshot and returns entry indexes
  plus reason codes. It does not delete or edit records.
- Strict privacy mode disables lexicon cleanup. Correction and term matching are
  stateless and produce no learning writes.
- Debug representations redact pinyin, term segments, and lexicon content.

The corpus contains repository regressions and first-party synthetic examples only.
