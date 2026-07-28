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
  "platform/windows_tsf/src/text_service.h"
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
  prediction_state_keeps_space_and_physical_digits_literal_at_the_host_boundary; do
  rg -q "fn ${test_name}" ime_core/tests/blind_typing_tests.rs
done
rg -q 'c_api_preserves_blind_typing_space_number_enter_and_escape_semantics' \
  ffi/ime_ffi/tests/c_api_tests.rs

python3 - <<'PY'
from pathlib import Path
from tempfile import TemporaryDirectory


def function_body(path: str, marker: str) -> str:
    source = Path(path).read_text(encoding="utf-8")
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"ABC-04 missing function marker {marker!r} in {path}")
    opening = source.find("{", start)
    if opening < 0:
        raise SystemExit(f"ABC-04 missing opening brace for {marker!r} in {path}")

    def skip_quoted(index: int, delimiter: str) -> int:
        index += len(delimiter)
        while index < len(source):
            if source.startswith(delimiter, index):
                return index + len(delimiter)
            if source[index] == "\\" and len(delimiter) == 1:
                index += 2
            else:
                index += 1
        raise SystemExit(f"ABC-04 unterminated string in {path}")

    def skip_block_comment(index: int) -> int:
        index += 2
        comment_depth = 1
        while index < len(source):
            if source.startswith("/*", index):
                comment_depth += 1
                index += 2
            elif source.startswith("*/", index):
                comment_depth -= 1
                index += 2
                if comment_depth == 0:
                    return index
            else:
                index += 1
        raise SystemExit(f"ABC-04 unterminated block comment in {path}")

    def skip_rust_raw_string(index: int):
        if source[index] != "r":
            return None
        cursor = index + 1
        while cursor < len(source) and source[cursor] == "#":
            cursor += 1
        if cursor >= len(source) or source[cursor] != '"':
            return None
        terminator = '"' + source[index + 1:cursor]
        ending = source.find(terminator, cursor + 1)
        if ending < 0:
            raise SystemExit(f"ABC-04 unterminated Rust raw string in {path}")
        return ending + len(terminator)

    depth = 0
    index = opening
    while index < len(source):
        if source.startswith("//", index):
            newline = source.find("\n", index + 2)
            index = len(source) if newline < 0 else newline + 1
            continue
        if source.startswith("/*", index):
            index = skip_block_comment(index)
            continue
        if source.startswith('"""', index):
            index = skip_quoted(index, '"""')
            continue
        raw_ending = skip_rust_raw_string(index)
        if raw_ending is not None:
            index = raw_ending
            continue
        if source[index] in {'"', "'"}:
            index = skip_quoted(index, source[index])
            continue
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
        index += 1
    raise SystemExit(f"ABC-04 missing closing brace for {marker!r} in {path}")


def require(body: str, token: str, label: str) -> None:
    if token not in body:
        raise SystemExit(f"ABC-04 missing {label}: {token!r}")


def forbid(body: str, token: str, label: str) -> None:
    if token in body:
        raise SystemExit(f"ABC-04 forbids {label}: {token!r}")


with TemporaryDirectory() as directory:
    parser_probe = Path(directory) / "parser_probe.rs"
    parser_probe.write_text(
        '''
fn parser_probe() {
    let quoted = "}";
    let raw = r#"}"#;
    // }
    /* } /* { */ } */
    parser_reached_real_end();
}
''',
        encoding="utf-8",
    )
    require(
        function_body(str(parser_probe), "fn parser_probe"),
        "parser_reached_real_end();",
        "string/comment-aware function-body parsing",
    )


session = function_body("ime_core/src/session.rs", "fn commit_punctuation")
require(
    session,
    "actual_candidate_index(BLIND_DEFAULT_CANDIDATE_INDEX)",
    "the named blind default in punctuation commit",
)

mac_map = function_body(
    "platform/macos_imk/Sources/MacKeyMapper.swift",
    "static func mapKeyDown",
)
require(mac_map, "case kVK_Space:", "macOS Space mapping")
require(mac_map, "case kVK_Return, kVK_ANSI_KeypadEnter:", "macOS Return mapping")

mac_handle = function_body(
    "platform/macos_imk/Sources/PrivatePinyinInputController.swift",
    "private func shouldHandle",
)
require(mac_handle, "case ImeKeyCodeValue.digit:", "macOS digit branch")
require(mac_handle, "return !currentPreedit.isEmpty", "macOS composition-only digit handling")
require(mac_handle, "return hasActiveInput", "macOS composition-scoped control handling")

windows_map = function_body(
    "platform/windows_tsf/src/key_map.cpp",
    "KeyMessage map_windows_key",
)
require(windows_map, "case VK_SPACE:", "Windows Space mapping")
require(windows_map, "case VK_RETURN:", "Windows Return mapping")

windows_scoped = function_body(
    "platform/windows_tsf/src/text_service.cpp",
    "bool is_composition_scoped_key",
)
forbid(windows_scoped, "IME_KEY_DIGIT", "prediction-scoped Windows digits")

windows_handle = function_body(
    "platform/windows_tsf/src/text_service.cpp",
    "bool TextService::should_handle_key",
)
require(windows_handle, "message.key_code == IME_KEY_DIGIT", "Windows digit branch")
require(windows_handle, "return has_composition_input_;", "Windows composition-only digit handling")
require(windows_handle, "return has_active_input_;", "Windows composition-scoped controls")

windows_state = function_body(
    "platform/windows_tsf/src/text_service.cpp",
    "void TextService::update_input_state",
)
require(
    windows_state,
    "has_composition_input_ = !output.preedit.empty();",
    "Windows composition state update",
)
header = Path("platform/windows_tsf/src/text_service.h").read_text(encoding="utf-8")
require(header, "bool has_composition_input_ = false;", "Windows composition state field")

ios_handle = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "private func handle(_ key: KeySpec)",
)
require(ios_handle, "case .space, .nineKeySpace:", "iOS Space handling")

ios_text = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func handleTextKey",
)
require(ios_text, "performCoreOutput(fallback: value)", "iOS literal text fallback")

ios_key_code = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func coreKeyCode",
)
require(ios_key_code, 'case "1", "2", "3", "4", "5", "6", "7", "8", "9":', "iOS digit mapping")
require(ios_key_code, "return IosKeyCodeValue.digit", "iOS shared digit key code")

ios_apply_or_insert = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func applyOrInsert",
)
require(
    ios_apply_or_insert,
    "let previousCompositionInput = !currentPreedit.isEmpty",
    "iOS composition-only fallback boundary",
)
require(
    ios_apply_or_insert,
    "if !previousCompositionInput && output?.shouldCommit != true",
    "iOS prediction-state literal insertion",
)
forbid(
    ios_apply_or_insert,
    "previousActiveInput = hasActiveInput",
    "iOS prediction candidates consuming literal digits",
)

ios_commit = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func commitCandidate(_ index: Int)",
)
require(ios_commit, "guard !candidateCommitInFlight,", "iOS duplicate-commit guard")
require(ios_commit, "currentCandidates.indices.contains(index)", "iOS visible index guard")
require(ios_commit, "core.commitCandidate(index: index)", "iOS explicit candidate commit")
PY

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
