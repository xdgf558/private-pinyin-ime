#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ai/model_manifest.schema.json"
  "ai/model_manifest.template.example.json"
  "ai/models/approved_models.json"
  "ai/local_ai_core/src/model_integrity.rs"
  "ai/local_ai_core/src/model_manifest.rs"
  "ai/local_ai_core/src/model_verifier.rs"
  "ai/local_ai_core/src/model_tests.rs"
  "tools/model_packager/Cargo.toml"
  "tools/model_packager/src/lib.rs"
  "tools/model_packager/src/main.rs"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required AI-05 file: $file" >&2
    exit 1
  fi
done

grep -q 'MODEL_MANIFEST_SCHEMA_VERSION: u32 = 1' \
  ai/local_ai_core/src/model_manifest.rs
grep -q 'MAX_AI_LITE_PACKAGE_BYTES' ai/local_ai_core/src/model_manifest.rs
grep -q 'owner_approved' ai/local_ai_core/src/model_verifier.rs
grep -q 'approval_fingerprint' ai/local_ai_core/src/model_verifier.rs
grep -q 'approval_registry: ModelApprovalRegistry::embedded()?' \
  ai/local_ai_core/src/model_verifier.rs
grep -q 'verify_package_artifact' ai/local_ai_core/src/model_verifier.rs
grep -q 'read_primary_model_bytes' ai/local_ai_core/src/model_verifier.rs
grep -q 'symbolic_link_artifacts_are_rejected' \
  ai/local_ai_core/src/model_tests.rs
grep -q 'manifest_self_approval_without_registry_approval_is_rejected' \
  ai/local_ai_core/src/model_tests.rs
grep -q 'artifact_is_reverified_when_bytes_are_opened_for_inference' \
  ai/local_ai_core/src/model_tests.rs
grep -q 'oversized_corrupt_artifact_is_rejected_before_loading' \
  ai/local_ai_core/src/model_tests.rs

python3 - <<'PY'
import json
from pathlib import Path

schema = json.loads(Path("ai/model_manifest.schema.json").read_text())
template = json.loads(Path("ai/model_manifest.template.example.json").read_text())
registry = json.loads(Path("ai/models/approved_models.json").read_text())

assert schema["properties"]["schema_version"]["const"] == 1
assert template["schema_version"] == 1
assert template["license"]["owner_approved"] is False
assert template["license"]["redistribution_allowed"] is False
assert template["privacy"] == {
    "runs_locally": True,
    "network_required": False,
    "stores_input": False,
}
assert all(item["sha256"] == "" and item["size_bytes"] == 0
           for item in template["artifacts"])
assert registry["schema_version"] == 1
assert isinstance(registry["approvals"], list)

approval_keys = set()
approval_ids = set()
for approval in registry["approvals"]:
    assert set(approval) == {
        "approval_id",
        "model_id",
        "version",
        "manifest_fingerprint_sha256",
    }
    assert approval["approval_id"] not in approval_ids
    approval_ids.add(approval["approval_id"])
    key = (approval["model_id"], approval["version"])
    assert key not in approval_keys
    approval_keys.add(key)
    assert len(approval["manifest_fingerprint_sha256"]) == 64

package_keys = set()
for package_root in sorted(path for path in Path("ai/models").iterdir() if path.is_dir()):
    manifest_path = package_root / "manifest.json"
    assert manifest_path.is_file(), f"missing manifest: {package_root}"
    manifest = json.loads(manifest_path.read_text())
    key = (manifest["id"], manifest["version"])
    assert key not in package_keys
    package_keys.add(key)
    assert key in approval_keys
    assert manifest["license"]["owner_approved"] is True
    assert manifest["license"]["redistribution_allowed"] is True
    assert manifest["privacy"] == {
        "runs_locally": True,
        "network_required": False,
        "stores_input": False,
    }

    declared_files = {"manifest.json"}
    for artifact in manifest["artifacts"]:
        artifact_path = package_root / artifact["path"]
        assert artifact_path.is_file()
        assert not artifact_path.is_symlink()
        data = artifact_path.read_bytes()
        assert len(data) == artifact["size_bytes"]
        import hashlib
        assert hashlib.sha256(data).hexdigest() == artifact["sha256"]
        declared_files.add(artifact["path"])

    actual_files = {
        str(path.relative_to(package_root))
        for path in package_root.rglob("*")
        if path.is_file()
    }
    assert actual_files == declared_files, (
        f"package {package_root} contains undeclared files: "
        f"{sorted(actual_files - declared_files)}"
    )

assert package_keys == approval_keys
PY

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' \
  ai/local_ai_core/src/model_integrity.rs \
  ai/local_ai_core/src/model_manifest.rs \
  ai/local_ai_core/src/model_verifier.rs; then
  echo "AI-05 runtime gates must not log model paths or package content." >&2
  exit 1
fi

bash scripts/check_no_external_ai_service.sh
cargo test -p private_pinyin_local_ai_core -p private_pinyin_model_packager

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/model"
printf '%s' 'synthetic-ai05-model' > "$temporary_directory/model/model.bin"
printf '%s\n' 'Synthetic AI-05 license notice' > "$temporary_directory/LICENSE.txt"
cp ai/model_manifest.template.example.json "$temporary_directory/template.json"
cargo run -q -p private_pinyin_model_packager -- \
  pack \
  --template "$temporary_directory/template.json" \
  --package-root "$temporary_directory" \
  --output "$temporary_directory/manifest.json"

python3 - "$temporary_directory/manifest.json" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text())
assert manifest["license"]["owner_approved"] is False
assert all(len(item["sha256"]) == 64 and item["size_bytes"] > 0
           for item in manifest["artifacts"])
PY

echo "AI-05 model supply-chain gates passed for every approved package."
