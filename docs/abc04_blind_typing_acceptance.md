# ABC-04 Blind-Typing Acceptance

ABC-04 closes the Intelligent-ABC-inspired interaction track without adding a
new decoder or ranker. The shared Rust session owns the key semantics; platform
hosts translate native events into that contract and must not implement a
second candidate-selection policy.

## Shared Key Contract

| Action | Active composition | No active composition |
|---|---|---|
| `Space` | Commit visible candidate 1, or raw input when no candidate exists | Insert one literal space, even when prediction candidates are visible |
| `1` through `9` | Commit the matching candidate on the current visible page | Pass through at the desktop host, even when prediction candidates are visible |
| Unavailable number slot | Preserve composition, page, and candidate identities | Pass through at the desktop host |
| `Enter` | Commit the raw full-key or nine-key composition | Let the host perform its normal Return behavior |
| `Escape` | Clear composition and candidates without committing | Let the host handle the key |
| `Backspace` | Remove one composition unit and recompute deterministically | Let the host delete document text |
| `PageUp` / `PageDown`, arrows, or the iOS expanded-grid controls | Move only between existing candidate pages; selection remains page-relative | Let the host handle the key |
| Chinese comma or period | Commit the same visible default as `Space`, followed by punctuation | Insert punctuation |

One accepted action produces at most one commit. An unavailable numbered slot,
stale optional-AI result, rapid duplicate candidate tap, or page boundary must
never commit hidden text or clear a recoverable composition.

Prediction candidates are advisory rather than physical-number targets. A user
who commits `你好` and immediately types `2` must get `你好2`; selecting a
prediction requires an explicit candidate click or tap.

Candidate 1 is the stable Space-key identity for a fixed input, context,
settings, and learning snapshot. Candidates 2 through 9 may be improved before
their page is first displayed, but an already visible page must not reorder
under the user's hand.

## Automated Evidence

- `ime_core/tests/blind_typing_tests.rs` exercises Space, numbered selection,
  unavailable slots, paging, Enter, Escape, Backspace/retype, punctuation,
  nine-key Space, and prediction-state behavior.
- `ffi/ime_ffi/tests/c_api_tests.rs` repeats the core Space, number, Enter, and
  Escape contract through the same C ABI used by all three hosts.
- `scripts/check_abc04_blind_typing.sh` requires the shared policy, tests,
  platform key mappings, one-commit iOS guard, documentation, and no content
  logging.

## Release Acceptance

Run the `ABC-04 blind typing` row in each platform section of
`docs/platform_smoke_test_plan.md`. Desktop testing must include a native text
editor and a Chromium/Electron host. iOS testing must cover QWERTY, nine-key,
compact candidates, expanded paging, rapid double taps, warm keyboard reuse,
and keyboard-extension recreation.

Evidence records may contain app/version names, pass/fail status, and
content-free timing or error codes. They must not retain typed text, candidate
content, learned phrases, or screenshots containing private user content.
