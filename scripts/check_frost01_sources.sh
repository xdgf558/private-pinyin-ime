#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rg >/dev/null 2>&1; then
  echo "FROST-01 source checks require ripgrep (rg)." >&2
  exit 1
fi

if rg -n '[“”‘’]' . --glob '*.ps1'; then
  echo "Windows PowerShell scripts must not contain smart quotes; PowerShell treats them as string delimiters." >&2
  exit 1
fi

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
grep -q 'if archive.len() != declared_entry_count' ime_core/src/reviewed_rime_frost.rs
grep -q 'let mode = unix_mode.ok_or' ime_core/src/reviewed_rime_frost.rs
grep -q 'write_canonical_tsv' ime_core/src/reviewed_rime_frost.rs
grep -q 'AtomicFile::create' ime_core/src/imported_lexicon.rs
grep -q 'member_without_unix_mode_is_rejected_without_overwriting' \
  ime_core/tests/reviewed_rime_frost_tests.rs
grep -q 'eocd_declared_entry_count_mismatch_is_rejected_without_overwriting' \
  ime_core/tests/reviewed_rime_frost_tests.rs
grep -q 'nonempty_zip_comment_is_accepted' \
  ime_core/tests/reviewed_rime_frost_tests.rs

grep -q 'rime_frost_lexicon_path' config/default_settings.json
grep -q 'rime_frost.tsv' platform/macos_imk/Sources/SettingsStore.swift
grep -q 'rime_frost.tsv' platform/windows_tsf/installer/open-settings.ps1
grep -q 'import-rime-frost' tools/settings_cli/src/main.rs
grep -q 'ime_engine_import_rime_frost_archive' ffi/c_api.h
grep -q 'ime_import_rime_frost_archive' ffi/c_api.h
grep -q 'ime_engine_clear_rime_frost_lexicon' ffi/c_api.h
grep -q 'reviewed-rime-frost = \["dep:sha2", "dep:zip"\]' ime_core/Cargo.toml
grep -q 'desktop-ai = \["local-ai", "reviewed-rime-frost"\]' ffi/ime_ffi/Cargo.toml
grep -q 'features = \["reviewed-rime-frost"\]' tools/settings_cli/Cargo.toml
for file in ime_core/src/lib.rs ime_core/src/api.rs ffi/ime_ffi/src/lib.rs; do
  grep -q '#\[cfg(feature = "reviewed-rime-frost")\]' "$file"
done

grep -q 'GPL-3.0' platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q '新版待审核' platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q 'GPL-3.0' platform/windows_tsf/installer/open-settings.ps1
grep -q '新版待审核' platform/windows_tsf/installer/open-settings.ps1
grep -q "$approved_sha" platform/macos_imk/Sources/PrivatePinyinRimeFrostManager.swift
grep -q "$approved_sha" platform/windows_tsf/installer/open-settings.ps1
grep -q "$approved_bytes" platform/windows_tsf/installer/open-settings.ps1
grep -q 'rime-frost-import' \
  platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q 'static func importReviewedRimeFrostArchive' \
  platform/macos_imk/Sources/CAbiBridge.swift
grep -q 'let rimeIceLexicon: PinyinEngineFileFingerprint' \
  platform/macos_imk/Sources/CAbiBridge.swift
grep -q 'let rimeFrostLexicon: PinyinEngineFileFingerprint' \
  platform/macos_imk/Sources/CAbiBridge.swift
grep -q 'a new White Frost file invalidates the shared-engine fingerprint' \
  platform/macos_imk/Tests/SharedEnginePoolTests.swift
grep -q 'a new Rime Ice file invalidates the shared-engine fingerprint' \
  platform/macos_imk/Tests/SharedEnginePoolTests.swift
if grep -q 'func importReviewedRimeFrostArchive(from path: String)' \
  platform/macos_imk/Sources/CAbiBridge.swift; then
  echo "White Frost archive import must not run while holding the shared-engine lock." >&2
  exit 1
fi
static_import="$(
  sed -n '/static func importReviewedRimeFrostArchive/,/^    }/p' \
    platform/macos_imk/Sources/CAbiBridge.swift
)"
printf '%s\n' "$static_import" | grep -q 'ime_import_rime_frost_archive'
if printf '%s\n' "$static_import" | grep -q 'ime_engine_new'; then
  echo "Static White Frost import must not construct a full input engine." >&2
  exit 1
fi
grep -q '\$currentSettings = Read-Settings' \
  platform/windows_tsf/installer/open-settings.ps1

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

ios_features="$(
  cargo tree -p private_pinyin_ime_ffi \
    --no-default-features \
    --features ios-ai \
    -e features
)"
ios_core_features="$(
  cargo tree -p private_pinyin_ime_ffi \
    --no-default-features \
    --features ios-ai \
    -e features \
    -i ime_core
)"
if printf '%s\n' "$ios_features" \
  | rg -q 'ime_core feature "reviewed-rime-frost"|(^| )zip v|(^| )zopfli v'
then
  echo "FROST-01 ZIP support leaked into the iOS FFI dependency graph." >&2
  exit 1
fi
if printf '%s\n' "$ios_core_features" \
  | rg -q 'ime_core feature "reviewed-rime-frost"'
then
  echo "Reviewed White Frost feature leaked into the iOS FFI graph." >&2
  exit 1
fi
ios_sha_tree="$(
  cargo tree -p private_pinyin_ime_ffi \
    --no-default-features \
    --features ios-ai \
    -i sha2 \
    2>/dev/null || true
)"
if printf '%s\n' "$ios_sha_tree" | rg -q 'ime_core v'; then
  echo "FROST-01 SHA-256 support leaked from ime_core into the iOS FFI graph." >&2
  exit 1
fi

desktop_features="$(
  cargo tree -p private_pinyin_ime_ffi \
    --no-default-features \
    --features desktop-ai \
    -e features \
    -i ime_core
)"
if ! printf '%s\n' "$desktop_features" \
  | rg -q 'ime_core feature "reviewed-rime-frost"'
then
  echo "Desktop FFI graph is missing reviewed White Frost support." >&2
  exit 1
fi

echo "FROST-01 source checks passed."
