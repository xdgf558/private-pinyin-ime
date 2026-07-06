# ffi

This directory contains the stable C ABI surface starting in stage 03.
Stage 6 adds settings-path loading plus user lexicon clear/export actions for desktop settings UI.

Files:

- `c_api.h`: public UTF-8 C ABI header.
- `ime_ffi`: Rust FFI crate that wraps `ime_core` and builds `libprivate_pinyin_ime`.
- `examples/c_demo.c`: C demo that creates an engine, feeds `nihao`, reads `你好`, and commits it.
- `SWIFT_CPP_INTEGRATION.md`: Swift and C++ calling notes.

Validation:

```bash
cargo test --workspace
bash scripts/run_c_demo.sh
```
