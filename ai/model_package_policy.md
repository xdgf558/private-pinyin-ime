# Local AI Model Package Policy

Status: AI-05 supply-chain gate

No local AI model is currently approved. The embedded registry at
`ai/models/approved_models.json` is intentionally empty, and no weight file is tracked
in this repository.

## Package Workflow

1. Prepare the model and its complete license notice in an external working directory.
2. Copy `ai/model_manifest.template.example.json` and fill in source, license,
   capabilities, platform, runtime, and hardware declarations. Keep
   `owner_approved` and `redistribution_allowed` false until legal/provenance review is
   complete.
3. Run:

   ```bash
   cargo run -p private_pinyin_model_packager -- \
     pack \
     --template /path/to/template.json \
     --package-root /path/to/package \
     --output /path/to/package/manifest.json
   ```

   The packager reads local files, computes streaming SHA-256 and byte sizes, writes the
   manifest atomically, and prints the approval fingerprint. It never downloads a model,
   changes the approval flags, or edits the repository approval registry.
4. The Owner reviews the exact source revision, redistribution terms, included notice,
   quality evidence, package size, platform scope, privacy declaration, and hardware
   requirements.
5. After redistribution review, set `redistribution_allowed` to true and rerun the
   packager so its printed fingerprint includes that decision. After final Owner
   approval, set only `owner_approved` to true and add the exact model ID, version, and
   printed fingerprint to `ai/models/approved_models.json` in a reviewed PR. The
   approval fingerprint excludes only the self-asserted `owner_approved` bit; it binds
   all artifact hashes/sizes and the remaining manifest policy.
6. Rebuild the signed application. Runtime verification requires both the manifest
   assertion and the independently embedded registry entry, then rechecks every file
   before loading it. The production verifier has no API for supplying an external
   registry; only the registry compiled into the application can authorize a package.

## Fail-Closed Checks

- Unknown manifest fields and malformed identifiers are rejected.
- Artifact paths must be bounded relative ASCII paths; absolute paths, parent traversal,
  Windows drive/ADS syntax, empty segments, and backslashes are rejected.
- Package roots, intermediate directories, and artifacts must not be symbolic links.
- Every artifact is verified by exact byte size and lowercase SHA-256. Verification
  stops as soon as a file exceeds its declared size. Primary model bytes are verified
  again while being read for inference.
- The declared platform must match the host. Writer-class models are prohibited on iOS.
- Privacy declarations must state local execution, no network requirement, and no input
  storage.
- AI Lite packages are capped at 64 MiB; Writer packages are capped at 4 GiB. A later
  stage may impose a lower product target.
- Model errors expose stable error codes and do not include paths, model content, or
  machine details.

## Hardware Tiers

| Tier | Detected memory | Default capability |
|---|---:|---|
| Tier 0 | below 8 GiB | model inference disabled |
| Tier 1 | 8 to below 16 GiB | AI Lite only |
| Tier 2 | 16 to below 24 GiB | Lite and explicitly approved Writer features |
| Tier 3 | 24 GiB or more | Lite and explicitly approved Writer features |

The manifest may require more memory or a GPU. AI-07 and AI-08 must supply trustworthy
platform memory/GPU profiles and calibrate real-device behavior before enabling a model.
