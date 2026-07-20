#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  "platform/ios_keyboard/PrivatePinyinC/IosAiSupport.h"
  "platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift"
  "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift"
)
for file in "${required_files[@]}"; do
  test -f "$file"
done

grep -q 'local-ai = ' ffi/ime_ffi/Cargo.toml
grep -q 'ios-ai = \["local-ai"\]' ffi/ime_ffi/Cargo.toml
grep -q 'IME_AI_PLATFORM_IOS = 3' ffi/c_api.h
grep -q 'ime_engine_enable_local_ai' ffi/c_api.h
grep -q 'ModelPlatform::Ios' ffi/ime_ffi/src/lib.rs
grep -q 'sync_channel::<AiRequest>' ai/local_ai_core/src/worker.rs
grep -q 'try_send(request)' ai/local_ai_core/src/worker.rs
grep -q 'ready.deadline.is_expired()' ffi/ime_ffi/src/local_ai.rs
grep -q 'ready.candidate_texts != current_texts' ffi/ime_ffi/src/local_ai.rs
grep -q '"runtime": "rust_compact"' \
  ai/models/private-pinyin-ai-lite-ranker-v1/manifest.json
grep -q '"size_bytes": 426' \
  ai/models/private-pinyin-ai-lite-ranker-v1/manifest.json

grep -q 'os_proc_available_memory' platform/ios_keyboard/PrivatePinyinC/IosAiSupport.h
grep -q 'ProcessInfo.processInfo.physicalMemory' \
  platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q 'private_pinyin_ios_available_memory_bytes' \
  platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q 'ime_engine_enable_local_ai' \
  platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q 'ime_session_set_secure_input' \
  platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q 'shouldDisableAiForCurrentInputContext' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'didReceiveMemoryWarning' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'localAiSuspendedForMemoryPressure = true' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'localAiSuspendedForMemoryPressure || shouldDisableAiForCurrentInputContext' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'case .phonePad, .namePhonePad, .numberPad, .decimalPad, .asciiCapableNumberPad' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift

grep -q -- '--features ios-ai' scripts/build_ios_keyboard.sh
grep -q -- '--features ios-ai' scripts/package_ios_app_store.sh
if grep -q -- '--features desktop-ai' scripts/build_ios_keyboard.sh \
  || grep -q -- '--features desktop-ai' scripts/package_ios_app_store.sh; then
  echo "iOS builds must use the isolated ios-ai feature, not desktop-ai." >&2
  exit 1
fi

grep -A1 'RequestsOpenAccess' platform/ios_keyboard/KeyboardExtension/Info.plist \
  | grep -q '<false/>'
if rg -n 'URLSession|NWConnection|Network\.framework|http://|https://' \
  --glob '*.swift' platform/ios_keyboard/KeyboardExtension; then
  echo "AI-08 must not add network APIs or URLs to the keyboard extension." >&2
  exit 1
fi
if rg -n '\.(gguf|onnx|safetensors|mlmodel|mlpackage)' \
  platform/ios_keyboard/KeyboardExtension platform/ios_keyboard/PrivatePinyinC; then
  echo "AI-08 must not embed or reference a heavy neural model in the keyboard extension." >&2
  exit 1
fi

echo "AI-08 iOS Lite integration source contract passed."
