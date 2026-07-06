# Swift and C++ Integration Notes

Stage 03 exposes the Rust engine through `ffi/c_api.h`. Platform hosts should
treat `ImeEngine`, `ImeSession`, and `ImeOutput` as owned handles and must not
access Rust internals directly.

## Ownership Rules

- Create one `ImeEngine` with `ime_engine_new(NULL)` for built-in defaults, or
  pass a UTF-8 JSON settings file path to load a settings snapshot. Free it with
  `ime_engine_free`.
- Create sessions with `ime_session_new(engine)` and free each session with
  `ime_session_free`.
- Every non-null `ImeOutput*` returned by the API must be released exactly once
  with `ime_output_free`.
- Every pointer-returning API may return `NULL` for invalid handles, internal
  errors, or caught Rust panics. Host code must check for null before reading.
- Strings and candidate pointers inside `ImeOutput` are valid only until
  `ime_output_free` is called for that output.
- All strings are UTF-8.
- `ImeEngine` and `ImeSession` are not thread-safe. Do not call into the same
  engine or session concurrently from multiple host threads.
- Use `ime_engine_clear_user_lexicon(engine)` and
  `ime_engine_export_user_lexicon(engine, path)` for settings UI actions. Both
  return `1` on success and `0` on invalid handles or internal errors.

## C++ Sketch

```cpp
#include "c_api.h"

#include <memory>

struct EngineDeleter {
  void operator()(ImeEngine* engine) const { ime_engine_free(engine); }
};

struct SessionDeleter {
  void operator()(ImeSession* session) const { ime_session_free(session); }
};

struct OutputDeleter {
  void operator()(ImeOutput* output) const { ime_output_free(output); }
};

using EnginePtr = std::unique_ptr<ImeEngine, EngineDeleter>;
using SessionPtr = std::unique_ptr<ImeSession, SessionDeleter>;
using OutputPtr = std::unique_ptr<ImeOutput, OutputDeleter>;

ImeKeyEvent textEvent(const char* text) {
  return ImeKeyEvent{IME_KEY_UNKNOWN, text, 0, 0, 0, 0, 0, 0};
}

void example() {
  EnginePtr engine(ime_engine_new(nullptr));
  if (!engine) {
    return;
  }
  SessionPtr session(ime_session_new(engine.get()));
  if (!session) {
    return;
  }
  OutputPtr output(ime_session_feed_key(session.get(), textEvent("n")));
  if (!output) {
    return;
  }
}
```

## Swift Sketch

Add `ffi/c_api.h` to the bridging header, then wrap raw pointers so each handle
has a single owner.

```swift
final class ImeEngineHandle {
    private let raw: OpaquePointer

    init?() {
        guard let engine = ime_engine_new(nil) else { return nil }
        self.raw = OpaquePointer(engine)
    }

    deinit {
        ime_engine_free(UnsafeMutablePointer<ImeEngine>(raw))
    }
}
```

Swift host code should copy UTF-8 strings out of `ImeOutput` before calling
`ime_output_free`.
