# macOS InputMethodKit Host

This directory will contain the macOS InputMethodKit prototype in stage 05.

The macOS host should remain thin:

- Convert key down events into core `ImeKeyEvent` values.
- Use marked text for composition.
- Render candidates through a macOS candidate UI.
- Commit selected text through the active client.
