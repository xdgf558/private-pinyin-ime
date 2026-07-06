# Windows TSF Host

This directory will contain the Windows Text Services Framework prototype in stage 04.

The Windows host should remain thin:

- Convert TSF key events into core `ImeKeyEvent` values.
- Update composition text from core output.
- Render candidates without taking focus.
- Commit selected text through TSF APIs.
