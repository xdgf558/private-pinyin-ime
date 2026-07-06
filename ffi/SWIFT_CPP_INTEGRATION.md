# Swift and C++ Integration Notes

Stage 03 exposes the Rust engine through `ffi/c_api.h`. Platform hosts should
treat `ImeEngine`, `ImeSession`, and `ImeOutput` as owned handles and must not
access Rust internals directly.

## Ownership Rules

- Create one `ImeEngine` with `ime_engine_new(NULL)` and free it with
  `ime_engine_free`.
- Create sessions with `ime_session_new(engine)` and free each session with
  `ime_session_free`.
- Every non-null `ImeOutput*` returned by the API must be released exactly once
  with `ime_output_free`.
- Strings and candidate pointers inside `ImeOutput` are valid only until
  `ime_output_free` is called for that output.
- All strings are UTF-8.
- FFI calls catch Rust panics and return `NULL` for pointer-returning functions.

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
  SessionPtr session(ime_session_new(engine.get()));
  OutputPtr output(ime_session_feed_key(session.get(), textEvent("n")));
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
