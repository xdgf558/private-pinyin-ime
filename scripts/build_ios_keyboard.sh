#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

rust_target="${IOS_RUST_TARGET:-aarch64-apple-ios-sim}"
sdk="${IOS_SDK:-iphonesimulator}"
configuration="${CONFIGURATION:-Debug}"
deployment_target="${IOS_DEPLOYMENT_TARGET:-18.0}"
app_bundle_id="${PRIVATE_PINYIN_IOS_APP_BUNDLE_ID:-com.privatepinyin.ios}"
keyboard_bundle_id="${PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID:-com.privatepinyin.ios.keyboard}"
app_group_id="${PRIVATE_PINYIN_IOS_APP_GROUP_ID:-group.com.privatepinyin.ios}"
project="$repo_root/platform/ios_keyboard/PrivatePinyin.xcodeproj"
derived_data="$repo_root/build/ios_keyboard"

if ! rustup target list --installed | grep -qx "$rust_target"; then
  echo "Missing Rust target: $rust_target" >&2
  echo "Install it with: rustup target add $rust_target" >&2
  exit 1
fi

export IPHONEOS_DEPLOYMENT_TARGET="$deployment_target"
cargo build -p private_pinyin_ime_ffi --release --target "$rust_target" --features ios-ai

xcodebuild \
  -project "$project" \
  -scheme PrivatePinyin \
  -configuration "$configuration" \
  -sdk "$sdk" \
  -derivedDataPath "$derived_data" \
  IOS_RUST_TARGET="$rust_target" \
  IPHONEOS_DEPLOYMENT_TARGET="$deployment_target" \
  PRIVATE_PINYIN_IOS_APP_BUNDLE_ID="$app_bundle_id" \
  PRIVATE_PINYIN_IOS_KEYBOARD_BUNDLE_ID="$keyboard_bundle_id" \
  PRIVATE_PINYIN_IOS_APP_GROUP_ID="$app_group_id" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "Built iOS keyboard app with Rust target $rust_target and iOS deployment target $deployment_target"
