# Tools

This directory contains development tools.

Current tools:

- `test_cli`: CLI smoke tool for checking candidate output from raw pinyin.
- `settings_cli`: CLI utility for writing settings snapshots, toggling strict privacy mode, clearing the user lexicon, and exporting the user lexicon.
- `lexicon_builder`: local lexicon conversion tool for project TSV, CC-CEDICT style files, mozillazg pinyin-data, and AOSP PinyinIME rawdict inputs.
- `ai_eval_runner`: evaluates required core regressions, rules-first opportunities, and the approved AI-06 Lite ranker from first-party offline corpora.
- `ai_benchmark`: reports engine initialization and lookup latency percentiles without using machine-dependent CI thresholds.
- `writer_feasibility`: validates one exact external Writer candidate/runtime pair and runs bounded first-party synthetic completion/rewrite probes, persisting only content-free Go/No-Go evidence.

Planned tools:

- Privacy and network-use checks.
