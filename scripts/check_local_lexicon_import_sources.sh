#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "ime_core/src/imported_lexicon.rs"
  "ime_core/tests/imported_lexicon_tests.rs"
  "docs/local_rime_lexicon_import.md"
  "platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

grep -q 'imported_lexicon_path' config/default_settings.json
grep -q 'MAX_RIME_SOURCE_BYTES' ime_core/src/imported_lexicon.rs
grep -q 'MAX_IMPORTED_FILE_BYTES' ime_core/src/imported_lexicon.rs
grep -q 'MAX_IMPORTED_ENTRIES' ime_core/src/imported_lexicon.rs
grep -q 'AtomicFile::create' ime_core/src/imported_lexicon.rs
grep -q 'ime_engine_import_rime_lexicon' ffi/c_api.h
grep -q 'ime_engine_clear_imported_lexicon' ffi/c_api.h
grep -q 'import-rime-lexicon' tools/settings_cli/src/main.rs
grep -q '导入 Rime 词库' platform/macos_imk/Sources/PrivatePinyinInputController.swift
grep -q '本地导入词库' platform/macos_imk/Sources/PrivatePinyinPreferencesWindowController.swift
grep -q '本地导入词库' platform/windows_tsf/installer/open-settings.ps1
grep -q 'importedLexiconURL' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q 'importRimeLexicons' platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
grep -q 'ime_engine_import_rime_lexicon' platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
if grep -q 'import PrivatePinyinC' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift; then
  echo "The shared iOS settings store must stay independent from the C import bridge." >&2
  exit 1
fi
if grep -q 'ime_engine_import_rime_lexicon\|processPendingRimeLexicons' \
  platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift; then
  echo "The iOS keyboard extension must not write the imported lexicon layer." >&2
  exit 1
fi
grep -q 'fileImporter' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'rime-ice' docs/local_rime_lexicon_import.md

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cargo run -q -p private_pinyin_settings -- write-default \
  --settings "$tmp_dir/settings.json" \
  --imported-lexicon "$tmp_dir/imported.tsv"

cat >"$tmp_dir/user.dict.yaml" <<'DATA'
---
name: private_pinyin_smoke
version: "1"
...
猫栈拼音	mao1 zhan4 pin1 yin1	9000
自动注音
DATA

cargo run -q -p private_pinyin_settings -- import-rime-lexicon \
  --settings "$tmp_dir/settings.json" \
  --input "$tmp_dir/user.dict.yaml"

grep -q $'^猫栈拼音\tmao zhan pin yin\t9000$' "$tmp_dir/imported.tsv"

cargo run -q -p private_pinyin_settings -- clear-imported-lexicon \
  --settings "$tmp_dir/settings.json"
test ! -e "$tmp_dir/imported.tsv"

echo "Local Rime lexicon import checks passed."
