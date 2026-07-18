#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

grep -q 'pub struct BoundedAiWorker' ai/local_ai_core/src/worker.rs
grep -q 'sync_channel::<AiRequest>' ai/local_ai_core/src/worker.rs
grep -q 'try_send(request)' ai/local_ai_core/src/worker.rs
grep -q 'verify_embedded_ai_lite' ai/local_ai_core/src/model_verifier.rs
grep -q 'desktop-ai' ffi/ime_ffi/Cargo.toml
grep -q 'ime_engine_enable_desktop_ai' ffi/c_api.h
grep -q 'ime_session_set_secure_input' ffi/c_api.h
grep -q 'AiRequestIdentity::new' ffi/ime_ffi/src/desktop_ai.rs
grep -q 'matches_current' ffi/ime_ffi/src/desktop_ai.rs
grep -q 'ready.deadline.is_expired()' ffi/ime_ffi/src/desktop_ai.rs
grep -q 'IsSecureEventInputEnabled' platform/macos_imk/Sources/CAbiBridge.swift
grep -q 'initguid.h' platform/windows_tsf/src/text_service.cpp
grep -q 'GUID_PROP_INPUTSCOPE' platform/windows_tsf/src/text_service.cpp
grep -q -- '--features desktop-ai' scripts/build_macos_imk.sh
grep -q -- '--features desktop-ai' scripts/build_windows_tsf.ps1

if grep -q -- '--features desktop-ai' scripts/build_ios_keyboard.sh; then
  echo "AI-07 desktop feature must not be linked into iOS builds." >&2
  exit 1
fi
if grep -q -- '--features desktop-ai' scripts/package_ios_app_store.sh; then
  echo "AI-07 desktop feature must not be linked into iOS App Store builds." >&2
  exit 1
fi

echo "AI-07 desktop integration source contract passed."
