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
| OI-009 | 02 | Commit first candidate before punctuation during composition | Medium | Codex | open | Stage 01 preserves input by committing raw pinyin plus punctuation; mature IME behavior should commit the top candidate plus punctuation, such as `你好,` for `nihao,` |
| OI-010 | 02 | Use range-prefix queries for SQLite user lexicon lookup | Medium | Codex | open | Replace `LIKE 'abc%'` with a bounded `compact_pinyin >= lower AND compact_pinyin < upper` query before large user lexicons |
| OI-011 | 02 | Preserve exact user lexicon matches before applying query limits | Medium | Codex | open | Current lookup limits SQL rows before in-memory exact/prefix partitioning, so high-frequency prefixes could crowd out lower-frequency exact matches |
| OI-012 | 02 | Fuse user and base ranking instead of unconditional user-first ordering | Medium | Codex | open | Stage 02 intentionally favors user entries; later ranking should prevent weak user prefix matches from outranking strong base exact matches |
| OI-013 | 02 | Wire sanitized user lexicon database failures into logging | Medium | Codex | open | DB failures must not interrupt input, but should emit structured error codes without raw user input, pinyin, or candidate text |
| OI-014 | 03 | Add C ABI settings loader for host-provided configuration | High | Codex | open | Stage 03 reserves `config_json_path`; later stages must expose user lexicon path, learning controls, and strict privacy mode through the C ABI |
| OI-015 | 04 | Add Windows code signing for TSF DLL and installer | High | Codex | open | Production Windows text service binaries must be signed before release |
| OI-016 | 04 | Build production Windows installer and uninstaller | High | Codex | open | Stage 04 only includes local `regsvr32` scripts; Stage 06 should provide packaged install/uninstall flow |
| OI-017 | 04 | Polish Windows candidate window for high DPI and dark mode | Medium | Codex | open | Stage 04 uses a simple non-activating candidate popup; production UI needs DPI-aware sizing, theming, and paging polish |
| OI-018 | 04 | Add Windows CI or manual validation record for TSF DLL loading | Medium | Codex | open | macOS local validation cannot load TSF; verify Notepad smoke test on Windows 11 before treating the host as user-ready |
