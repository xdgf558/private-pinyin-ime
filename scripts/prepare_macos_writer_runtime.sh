#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:?usage: prepare_macos_writer_runtime.sh DESTINATION}"
cache_dir="$repo_root/build/writer_runtime/macos-arm64"
archive="$cache_dir/llama-b10069-bin-macos-arm64.tar.gz"
extract_dir="$cache_dir/extracted"
url="https://github.com/ggml-org/llama.cpp/releases/download/b10069/llama-b10069-bin-macos-arm64.tar.gz"
expected_sha="022469e0b22f4b84dcd0a323867d7f5a31dae21894931ee6a24a35abd2a60359"

mkdir -p "$cache_dir"
if [ ! -f "$archive" ] || [ "$(shasum -a 256 "$archive" | awk '{print $1}')" != "$expected_sha" ]; then
  rm -f "$archive"
  curl --fail --location --retry 3 --output "$archive" "$url"
fi

actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [ "$actual_sha" != "$expected_sha" ]; then
  echo "Writer runtime SHA-256 mismatch." >&2
  exit 1
fi

rm -rf "$extract_dir" "$destination"
mkdir -p "$extract_dir" "$destination"
tar -xzf "$archive" -C "$extract_dir"
runtime_dir="$(find "$extract_dir" -type f -name llama-server -print -quit | xargs dirname)"
test -n "$runtime_dir"

cp "$runtime_dir/llama-server" "$destination/llama-server"
find "$runtime_dir" -maxdepth 1 \( -type f -o -type l \) -name '*.dylib' \
  -exec cp -P {} "$destination/" \;
cp "$runtime_dir/LICENSE" "$destination/llama.cpp-LICENSE"
chmod 755 "$destination/llama-server"

# The official archive uses versioned dylibs plus sibling compatibility symlinks.
# Running the binary here turns an incomplete dependency copy into a build failure.
"$destination/llama-server" --version >/dev/null
help_output="$("$destination/llama-server" --help 2>&1)"
for option in --api-key-file --offline --no-webui --log-disable --parallel --ctx-size --batch-size --ubatch-size; do
  if ! grep -q -- "$option" <<<"$help_output"; then
    echo "Writer runtime is missing required option: $option" >&2
    exit 1
  fi
done

echo "Prepared macOS Writer runtime at $destination"
