# macOS InputMethodKit Notes

Stage 5 will implement the macOS InputMethodKit host.

## Target

- macOS 14 or newer.
- Swift with Objective-C bridge where needed.
- InputMethodKit app bundle.
- Calls the shared Rust core through the C ABI.

## Required References

- Apple InputMethodKit documentation.

## Constraints

- Use marked text for composition.
- Candidate UI should follow the insertion point.
- Do not access the network by default.
