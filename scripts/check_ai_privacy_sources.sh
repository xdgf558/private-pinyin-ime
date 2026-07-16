#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ai/local_ai_core/src/privacy_guard.rs"
  "ai/local_ai_core/src/request_builder.rs"
  "ai/local_ai_core/src/privacy_tests.rs"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required AI privacy file: $file" >&2
    exit 1
  fi
done

grep -q 'struct PrivacyGuard' ai/local_ai_core/src/privacy_guard.rs
grep -q 'struct AiFeaturePolicy' ai/local_ai_core/src/privacy_guard.rs
grep -q 'MAX_RECENT_TOKENS: usize = 8' ai/local_ai_core/src/privacy_guard.rs
grep -q 'InputRejectedByPrivacyGuard' ai/local_ai_core/src/privacy_guard.rs
grep -q 'requires_explicit_user_action' ai/local_ai_core/src/privacy_guard.rs
grep -q 'struct AiRequestBuilder' ai/local_ai_core/src/request_builder.rs
grep -q 'NineKeyDigits' ai/local_ai_core/src/request.rs
grep -q '^    pub(crate) fn new_at' ai/local_ai_core/src/request.rs
grep -q 'secure_input_is_rejected_with_a_code_only_error' \
  ai/local_ai_core/src/privacy_tests.rs
grep -q 'password_and_one_time_code_samples_are_rejected' \
  ai/local_ai_core/src/privacy_tests.rs
grep -q 'oversized_raw_pinyin_and_composition_are_rejected' \
  ai/local_ai_core/src/privacy_tests.rs

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' ai/local_ai_core/src; then
  echo "Local AI runtime must not log request, response, prompt, or context content." >&2
  exit 1
fi

if rg -n '(clipboard|surrounding_document|app_document|webpage_content|email_body|chat_history|screenshot)' \
  ai/local_ai_core/src/request.rs ai/local_ai_core/src/request_builder.rs; then
  echo "Local AI request contracts must not expose forbidden application context." >&2
  exit 1
fi

cargo test -p private_pinyin_local_ai_core

echo "Local AI privacy source checks passed."
