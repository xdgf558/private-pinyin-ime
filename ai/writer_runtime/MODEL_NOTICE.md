# Desktop Writer V1 Model Notice

The desktop Writer model is not part of this repository, application bundle, installer,
or automatic update. A macOS or Windows user may explicitly request a download from the
fixed official upstream location below. The project does not redistribute the model.

| Field | Value |
|---|---|
| Model | Qwen2.5 1.5B Instruct GGUF Q4_K_M |
| Upstream | `Qwen/Qwen2.5-1.5B-Instruct-GGUF` |
| Revision | `dd26da440ef0330c47919d1ecae0966d24022222` |
| File | `qwen2.5-1.5b-instruct-q4_k_m.gguf` |
| Size | `1,117,320,736` bytes |
| SHA-256 | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |
| License | Apache-2.0 |
| Product policy | User-initiated download and local use only; redistribution disabled |

The packaged runtime is llama.cpp release `b10069`, revision
`178a6c44937154dc4c4eff0d166f4a044c4fceba`, under the MIT license. macOS arm64 and
Windows x64 archives are pinned by SHA-256 in
`desktop_writer_runtime_manifest.json` and verified before packaging.

Hosts verify the model during download, and the Helper verifies the complete size and
SHA-256 again before every load. A mismatch fails closed. Input and output content never
enters the model download URL, process arguments, logs, telemetry, or persistent caches.
