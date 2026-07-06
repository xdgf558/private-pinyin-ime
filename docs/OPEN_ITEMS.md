# Open Items

| ID | Stage | Item | Priority | Owner | Status | Notes |
|---|---|---|---|---|---|---|
| OI-001 | 01 | Replace sample lexicon with licensed production lexicon | High | TBD | open | Must verify license before release |
| OI-002 | 00 | Select final project license | Medium | Owner | open | Repository currently uses all-rights-reserved text |
| OI-003 | 01 | Implement Rust core engine crate | High | Codex | closed | Completed in stage 01 local branch |
| OI-004 | 01 | Add minimal GitHub Actions for Rust validation | High | Codex | closed | Completed in stage 01 local branch |
| OI-005 | 01 | Keep runtime data outside source directories | Medium | Codex | open | Development-only sandbox data may use ignored `local/`; production code should use platform data directories |
| OI-006 | 02 | Add indexed lexicon lookup before production dictionary scale | High | Codex | open | Current stage-01 lookup is linear over the sample lexicon; use trie or sorted-prefix index before large dictionaries |
| OI-007 | 04 | Refine Shift toggle to key-up-only semantics in platform hosts | Medium | Codex | open | Stage 01 toggles on a synthetic Shift key event; real hosts should distinguish standalone Shift release from Shift+letter |
| OI-008 | 03 | Implement candidate paging for page up/down and page-size settings | Medium | Codex | open | `candidate_page`, `candidate_page_size`, PageUp, and PageDown are intentionally staged beyond stage 01 |
