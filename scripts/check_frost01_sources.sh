#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ime_core/src/reviewed_rime_frost.rs"
  "ime_core/tests/reviewed_rime_frost_tests.rs"
  "platform/macos_imk/Sources/PrivatePinyinRimeFrostManager.swift"
  "platform/windows_tsf/installer/open-settings.ps1"
  "docs/rime_frost_integration.md"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

approved_sha="4f4998ae83f63d757c0a4ace192f69d48265bddfabe231642b73e3739ed0f2f5"
approved_bytes="44008360"
approved_version="1.0.4"

grep -q "RIME_FROST_APPROVED_VERSION: &str = \"$approved_version\"" \
  ime_core/src/reviewed_rime_frost.rs
grep -q "RIME_FROST_ARCHIVE_BYTES: u64 = 44_008_360" \
  ime_core/src/reviewed_rime_frost.rs
grep -q "$approved_sha" ime_core/src/reviewed_rime_frost.rs
grep -q 'gaboolic/rime-frost/releases/download/1.0.4/rime-frost-schemas.zip' \
  ime_core/src/reviewed_rime_frost.rs
grep -q 'github.com/gaboolic/rime-frost/blob/master/LICENSE' \
  ime_core/src/reviewed_rime_frost.rs
grep -q 'const MAX_ARCHIVE_ENTRIES: usize = 256' ime_core/src/reviewed_rime_frost.rs
grep -q 'const MAX_ARCHIVE_EXPANDED_BYTES: u64 = 128 \* 1024 \* 1024' \
  ime_core/src/reviewed_rime_frost.rs
grep -q 'const MAX_ARCHIVE_MEMBER_BYTES: u64 = 32 \* 1024 \* 1024' \
  ime_core/src/reviewed_rime_frost.rs
grep -q 'const MAX_COMPRESSION_RATIO: u64 = 200' ime_core/src/reviewed_rime_frost.rs
grep -q 'validate_member_name' ime_core/src/reviewed_rime_frost.rs
grep -q 'validate_member_type' ime_core/src/reviewed_rime_frost.rs
grep -q 'write_canonical_tsv' ime_core/src/reviewed_rime_frost.rs
grep -q 'AtomicFile::create' ime_core/src/imported_lexicon.rs

grep -q 'rime_frost_lexicon_path' config/default_settings.json
grep -q 'rime_frost.tsv' platform/macos_imk/Sources/SettingsStore.swift
grep -q 'rime_frost.tsv' platform/windows_tsf/installer/open-settings.ps1
grep -q 'import-rime-frost' tools/settings_cli/src/main.rs
grep -q 'ime_engine_import_rime_frost_archive' ffi/c_api.h
grep -q 'ime_engine_clear_rime_frost_lexicon' ffi/c_api.h

grep -q 'GPL-3.0' platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q '新版待审核' platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q 'GPL-3.0' platform/windows_tsf/installer/open-settings.ps1
grep -q '新版待审核' platform/windows_tsf/installer/open-settings.ps1
grep -q "$approved_sha" platform/macos_imk/Sources/PrivatePinyinRimeFrostManager.swift
grep -q "$approved_sha" platform/windows_tsf/installer/open-settings.ps1
grep -q "$approved_bytes" platform/windows_tsf/installer/open-settings.ps1

grep -q 'ImportedLexiconLimits::new(64 \* 1024 \* 1024, 128 \* 1024 \* 1024, 750_000)' \
  ime_core/src/imported_lexicon.rs
grep -q 'ImportedLexiconLimits::new(16 \* 1024 \* 1024, 32 \* 1024 \* 1024, 200_000)' \
  ime_core/src/imported_lexicon.rs
grep -q '## Decision 044: Reviewed Opt-In White Frost Desktop Layer' docs/DECISIONS.md
grep -q '新版待审核' docs/rime_frost_integration.md
grep -q "$approved_sha" docs/rime_frost_integration.md

if rg -n '白霜拼音|rime_frost|rime-frost' platform/ios_keyboard; then
  echo "FROST-01 must remain desktop-only; iOS contains White Frost integration." >&2
  exit 1
fi

echo "FROST-01 source checks passed."
