#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null 2>&1; then
  if [[ "${PRIVATE_PINYIN_REQUIRE_SWIFTC:-0}" == "1" ]]; then
    echo "swiftc is required for macOS candidate selection tests." >&2
    exit 1
  fi
  echo "swiftc is unavailable; macOS candidate selection tests skipped."
  exit 0
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
mkdir -p "$temporary_dir/module-cache"

swiftc \
  -module-cache-path "$temporary_dir/module-cache" \
  platform/macos_imk/Sources/PrivatePinyinCandidateSelectionState.swift \
  platform/macos_imk/Tests/CandidateSelectionStateTests.swift \
  -o "$temporary_dir/candidate-selection-tests"

"$temporary_dir/candidate-selection-tests"

python3 - <<'PY'
from pathlib import Path

path = Path("platform/macos_imk/Sources/PrivatePinyinInputController.swift")
source = path.read_text(encoding="utf-8")
start_marker = "@objc(candidateSelected:)"
end_marker = "@objc(candidateSelectionChanged:)"
start = source.find(start_marker)
end = source.find(end_marker, start + len(start_marker))
if start < 0 or end < 0:
    raise SystemExit("macOS candidate controller callback markers are missing")

body = source[start:end]
if "candidate_selection_unresolved" not in body:
    raise SystemExit("unresolved candidate callbacks must remain diagnosable")
for forbidden in ("commitText(reportedText)", "resetComposition()"):
    if forbidden in body:
        raise SystemExit(
            f"unresolved candidate callbacks must not mutate composition: {forbidden}"
        )
PY
