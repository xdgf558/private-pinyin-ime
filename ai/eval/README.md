# Offline AI Evaluation Data

`baseline_cases.tsv` freezes a small, auditable view of the current input engine
before any AI provider is introduced. It deliberately separates two kinds of cases:

- `required`: behavior already supported by the shared Rust core. Regressions fail the
  evaluation command and CI.
- `observe`: product opportunities such as typo correction, mixed English terms, and
  mixed full-pinyin/initial input. Misses are reported but do not fail AI-01.

## Data policy

Every row must use one of these provenance values:

- `project_regression`: derived from an existing public repository test or documented bug.
- `synthetic`: manually written for this project and not copied from user input.

The parser rejects any other provenance. Do not add exported user lexicons, support
messages, real application text, telemetry, prompts, or private typing samples. The
dataset contains no user identifiers and no surrounding application context.

## Schema

```text
id  feature  input_kind  input  expected_texts  max_rank  gate  provenance
```

Fields are tab-separated. Multiple acceptable outputs use `|`. Supported input kinds
are `raw_pinyin` and `nine_key`.

## Commands

Run the deterministic quality baseline:

```bash
bash scripts/run_ai_eval.sh
```

Emit machine-readable output:

```bash
bash scripts/run_ai_eval.sh --json
```

Run the AI-04 rules-first quality gate:

```bash
bash scripts/run_ai_eval.sh --rules --require-observed-successes 7
```

Rules mode prepends only bounded correction or canonical English-term suggestions for
the synthetic opportunity cases. It does not connect the rule engine to a platform host
or change the production input path.

Run the AI-06 approved Lite-ranker quality gate:

```bash
bash scripts/run_ai_eval.sh --ranker --require-ranker-improvements 8
```

`ai06_ranker_cases.json` is a strict first-party JSON dataset with eight improvement
cases and four preservation cases. The gate compares baseline Top-1/MRR with the verified
ranker, requires all targeted improvements, and rejects any preservation regression. Its
content declarations prohibit user data, real application context, prompts, model
outputs, and network dependencies.

Capture report-only latency measurements in a release build:

```bash
bash scripts/run_ai_eval.sh --benchmark --lookup-iterations 50
```

Latency is intentionally not a CI pass/fail gate in AI-01 because shared runners and
developer hardware are not comparable. Performance gates will be calibrated from
platform measurements before AI Lite integration.
