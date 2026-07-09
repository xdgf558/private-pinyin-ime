# ime_core

This directory contains the shared Rust core engine.

Current responsibilities:

- Pinyin parsing.
- Candidate generation from the embedded starter lexicon.
- Ranking.
- SQLite user lexicon persistence and one-step user bigram learning.
- Local bigram prediction.
- Settings and privacy enforcement.
- JSON settings snapshots.
- User lexicon clear/export actions.
