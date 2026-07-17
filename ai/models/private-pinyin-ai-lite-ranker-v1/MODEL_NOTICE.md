# PrivatePinyin AI Lite Ranker Notice

Model ID: `private-pinyin.ai-lite-ranker`

Version: `1.0.0`

This package contains first-party, hand-calibrated fixed-point coefficients for the
PrivatePinyin local candidate ranker. It was created from repository-owned regression
cases and synthetic examples only. It was not trained on exported user lexicons,
telemetry, private typing samples, prompts, third-party model output, or network data.

The coefficients and accompanying evaluation data are distributed under the repository
license. The ranker runs locally, requires no network access, and does not store input.
