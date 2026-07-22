#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

manifest="ai/writer_runtime/desktop_writer_runtime_manifest.json"
runtime="ai/helper/private_pinyin_ai_helper/src/writer_runtime.rs"
mac_manager="platform/macos_imk/Sources/PrivatePinyinWriterModelManager.swift"
windows_writer="platform/windows_tsf/installer/open-writer.ps1"

python3 - "$manifest" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)

assert manifest["schema_version"] == 1
assert manifest["release_profile"] == "on_demand_desktop_writer_v1"
assert manifest["owner_approved_for_on_demand_download"] is True
assert manifest["redistribution_allowed"] is False
assert manifest["platforms"] == ["macos-arm64", "windows-x64"]
assert manifest["features"] == {
    "explicit_rewrite": True,
    "explicit_translation": True,
    "automatic_short_completion": False,
    "strict_privacy_disables_writer": True,
}
assert manifest["runtime"]["name"] == "llama.cpp"
assert manifest["runtime"]["tag"] == "b10069"
assert manifest["runtime"]["revision"] == "178a6c44937154dc4c4eff0d166f4a044c4fceba"
assert manifest["runtime"]["license"] == "MIT"
assert manifest["model"]["id"] == "qwen2.5-1.5b-instruct-q4-k-m"
assert manifest["model"]["size_bytes"] == 1117320736
assert manifest["model"]["sha256"] == "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
assert manifest["model"]["license"] == "Apache-2.0"
assert manifest["model"]["bundled"] is False
PY

if [ -n "$(git ls-files '*.gguf' '*.safetensors' '*.onnx' '*.mlmodel' '*.mlpackage')" ]; then
  echo "Writer model weights must not be committed or bundled." >&2
  exit 1
fi

grep -q 'WRITER_MODEL_SIZE_BYTES: u64 = 1_117_320_736' "$runtime"
grep -q '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e' "$runtime"
grep -q -- '"--host"' "$runtime"
grep -q '"127.0.0.1"' "$runtime"
grep -q -- '"--no-webui"' "$runtime"
grep -q -- '"--offline"' "$runtime"
grep -q -- '"--log-disable"' "$runtime"
grep -q 'Stdio::null()' "$runtime"

grep -q 'expectedSize: Int64 = 1_117_320_736' "$mac_manager"
grep -q '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e' "$mac_manager"
grep -q 'URLSessionConfiguration.ephemeral' "$mac_manager"
grep -q 'posixPermissions: 0o600' "$mac_manager"
grep -q 'writerRunIsAllowed()' platform/macos_imk/Sources/PrivatePinyinWriterWindowController.swift
grep -q 'privatePinyinSettingsChanged' platform/macos_imk/Sources/PrivatePinyinWriterWindowController.swift
grep -q '生成结果已丢弃' platform/macos_imk/Sources/PrivatePinyinWriterWindowController.swift

grep -q '\$modelSize = \[int64\]1117320736' "$windows_writer"
grep -q '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e' "$windows_writer"
grep -q 'Get-FileHash -Algorithm SHA256' "$windows_writer"
grep -q 'PRIVATE_PINYIN_AI_HELPER_TOKEN' "$windows_writer"
grep -q '\.Arguments = "--stdio --idle-timeout-ms 600000"' "$windows_writer"
grep -q 'enable_short_completion = \$false' "$windows_writer"
grep -q 'Read-ExactWithDeadline' "$windows_writer"
grep -q '\.AddSeconds(45)' "$windows_writer"
grep -q 'Writer 设置已变化，本次请求已取消' "$windows_writer"
grep -q '生成结果已丢弃' "$windows_writer"

grep -q 'prepare_macos_writer_runtime.sh' scripts/build_macos_imk.sh
grep -q 'helpers_dir/WriterRuntime' scripts/build_macos_imk.sh
grep -q '\\( -type f -o -type l \\)' scripts/prepare_macos_writer_runtime.sh
grep -q 'llama-server.*--version' scripts/prepare_macos_writer_runtime.sh
grep -q 'prepare_windows_writer_runtime.ps1' scripts/package_windows_tsf.ps1
grep -q 'writerRuntimeDir = Join-Path \$stageDir "WriterRuntime"' scripts/package_windows_tsf.ps1
grep -q 'WriterRuntime\\llama-server.exe' platform/windows_tsf/installer/PrivatePinyinTsf.wxs
grep -q 'File /r "\${PACKAGE_SOURCE}\\WriterRuntime\\\*"' platform/windows_tsf/installer/PrivatePinyinTsf.nsi
grep -q 'PrivatePinyinWriterWindowController.swift' scripts/build_macos_imk.sh
grep -q 'open-writer.ps1' scripts/package_windows_tsf.ps1

echo "Desktop Writer runtime source contract passed."
