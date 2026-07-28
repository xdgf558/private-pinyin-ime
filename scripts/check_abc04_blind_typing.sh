#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rg >/dev/null 2>&1; then
  echo "ABC-04 source contract requires ripgrep (rg)." >&2
  exit 1
fi

required_files=(
  "ime_core/src/blind_typing.rs"
  "ime_core/src/session.rs"
  "ime_core/tests/blind_typing_tests.rs"
  "ffi/ime_ffi/tests/c_api_tests.rs"
  "platform/macos_imk/Sources/MacKeyMapper.swift"
  "platform/macos_imk/Sources/PrivatePinyinInputController.swift"
  "platform/windows_tsf/src/key_map.cpp"
  "platform/windows_tsf/src/text_service.cpp"
  "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift"
  "docs/abc04_blind_typing_acceptance.md"
  "docs/DECISIONS.md"
  "docs/DEVELOPMENT_PROGRESS.md"
  "docs/platform_smoke_test_plan.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required ABC-04 file: $file" >&2
    exit 1
  fi
done

rg -q 'BLIND_DEFAULT_CANDIDATE_INDEX: usize = 0' ime_core/src/blind_typing.rs
rg -q 'LAST_NUMBERED_CANDIDATE_KEY: u8 = 9' ime_core/src/blind_typing.rs
rg -q 'pub fn numbered_candidate_index' ime_core/src/blind_typing.rs
rg -q 'numbered_candidate_index\(index, visible_candidate_count\)' ime_core/src/session.rs
rg -q 'commit_candidate\(BLIND_DEFAULT_CANDIDATE_INDEX\)' ime_core/src/session.rs

for test_name in \
  space_commits_the_visible_default_exactly_once \
  numbered_keys_select_only_the_current_visible_page \
  paging_then_number_selection_commits_the_displayed_identity \
  enter_escape_and_backspace_keep_recovery_predictable \
  punctuation_uses_the_same_default_as_space \
  nine_key_space_commits_the_visible_default \
  prediction_state_keeps_space_literal_and_number_selection_explicit; do
  rg -q "fn ${test_name}" ime_core/tests/blind_typing_tests.rs
done
rg -q 'c_api_preserves_blind_typing_space_number_enter_and_escape_semantics' \
  ffi/ime_ffi/tests/c_api_tests.rs

rg -q 'case kVK_Space:' platform/macos_imk/Sources/MacKeyMapper.swift
rg -q 'case kVK_Return, kVK_ANSI_KeypadEnter:' \
  platform/macos_imk/Sources/MacKeyMapper.swift
rg -q 'ImeKeyCodeValue\.digit:' \
  platform/macos_imk/Sources/PrivatePinyinInputController.swift
rg -q 'return hasActiveInput' platform/macos_imk/Sources/PrivatePinyinInputController.swift

rg -q 'case VK_SPACE:' platform/windows_tsf/src/key_map.cpp
rg -q 'case VK_RETURN:' platform/windows_tsf/src/key_map.cpp
rg -q 'case IME_KEY_DIGIT:' platform/windows_tsf/src/text_service.cpp
rg -q 'return has_active_input_;' platform/windows_tsf/src/text_service.cpp

rg -q 'case \.space, \.nineKeySpace:' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
rg -q 'guard !candidateCommitInFlight,' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
rg -q 'core\.commitCandidate\(index: index\)' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift

rg -q 'Decision 050: Shared Blind-Typing Key Contract' docs/DECISIONS.md
rg -q '\| OI-053 \| ABC-04 .*\| closed \|' docs/OPEN_ITEMS.md
test "$(grep -c '| ABC-04 blind typing |' docs/platform_smoke_test_plan.md)" -eq 3
rg -q 'Current stage: ABC-04 blind-typing interaction and acceptance' \
  docs/DEVELOPMENT_PROGRESS.md

if rg -n '(println!|eprintln!|dbg!|log::|tracing::)' ime_core/src/blind_typing.rs; then
  echo "ABC-04 must not log input or candidate content." >&2
  exit 1
fi

echo "ABC-04 blind-typing source contract passed."
