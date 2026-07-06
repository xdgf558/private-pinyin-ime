#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

cargo build -p private_pinyin_ime_ffi
cc ffi/examples/c_layout_check.c -std=c11 -Iffi -o target/debug/ime_c_layout_check
cc ffi/examples/c_demo.c -Iffi -Ltarget/debug -lprivate_pinyin_ime -o target/debug/ime_c_demo

case "$(uname -s)" in
  Darwin)
    export DYLD_LIBRARY_PATH="${PWD}/target/debug${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
    ;;
  Linux)
    export LD_LIBRARY_PATH="${PWD}/target/debug${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    ;;
esac

target/debug/ime_c_layout_check
target/debug/ime_c_demo
