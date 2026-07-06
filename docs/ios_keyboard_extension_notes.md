# iOS Keyboard Extension Notes

Stage 7 will implement the iOS keyboard extension.

## Target

- iOS 18 or newer.
- Container app plus custom keyboard extension.
- Shared Rust core compiled as an iOS static library.

## Required Defaults

- `RequestsOpenAccess` must be `false`.
- No network access in the first iOS version.
- Include a Globe or Next Keyboard key.

## Constraints

- Password and phone fields may force the system keyboard.
- User lexicon storage requires explicit user opt-in and App Group planning.
