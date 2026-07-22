#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  "platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj"
  "platform/ios_keyboard/PrivatePinyin.xcodeproj/xcshareddata/xcschemes/PrivatePinyin.xcscheme"
  "platform/ios_keyboard/PrivatePinyinC/module.modulemap"
  "platform/ios_keyboard/PrivatePinyinC/IosAiSupport.h"
  "platform/ios_keyboard/ContainerApp/PrivatePinyinApp.swift"
  "platform/ios_keyboard/ContainerApp/ContentView.swift"
  "platform/ios_keyboard/ContainerApp/IosSettingsStore.swift"
  "platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift"
  "platform/ios_keyboard/ContainerApp/Assets.xcassets/BrandMark.imageset/Contents.json"
  "platform/ios_keyboard/ContainerApp/Info.plist"
  "platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements"
  "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift"
  "platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift"
  "platform/ios_keyboard/Tests/ChineseTextConverterRegression.swift"
  "platform/ios_keyboard/KeyboardExtension/Info.plist"
  "platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements"
  "scripts/build_ios_keyboard.sh"
  "scripts/test_ios_chinese_transform.sh"
)

for file in "${required_files[@]}"; do
  test -f "$file"
done

if command -v plutil >/dev/null 2>&1; then
  plutil -lint platform/ios_keyboard/ContainerApp/Info.plist >/dev/null
  plutil -lint platform/ios_keyboard/KeyboardExtension/Info.plist >/dev/null
  plutil -lint platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements >/dev/null
  plutil -lint platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements >/dev/null
else
  grep -q "<plist version=\"1.0\">" platform/ios_keyboard/KeyboardExtension/Info.plist
  grep -q "</plist>" platform/ios_keyboard/KeyboardExtension/Info.plist
fi

grep -q "UIInputViewController" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "advanceToNextInputMode" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "needsInputModeSwitchKey" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "RequestsOpenAccess" platform/ios_keyboard/KeyboardExtension/Info.plist
grep -A1 "RequestsOpenAccess" platform/ios_keyboard/KeyboardExtension/Info.plist | grep -q "<false/>"
grep -q "PRIVATE_PINYIN_IOS_APP_GROUP_ID" platform/ios_keyboard/ContainerApp/PrivatePinyin.entitlements
grep -q "PRIVATE_PINYIN_IOS_APP_GROUP_ID" platform/ios_keyboard/KeyboardExtension/PrivatePinyinKeyboard.entitlements
grep -q "PRIVATE_PINYIN_IOS_APP_GROUP_ID = group.com.privatepinyin.ios" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "PrivatePinyinAppGroupIdentifier" platform/ios_keyboard/ContainerApp/Info.plist
grep -q "PrivatePinyinAppGroupIdentifier" platform/ios_keyboard/KeyboardExtension/Info.plist
grep -q "CODE_SIGN_ENTITLEMENTS = ContainerApp/PrivatePinyin.entitlements" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "CODE_SIGN_ENTITLEMENTS = KeyboardExtension/PrivatePinyinKeyboard.entitlements" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "default_settings.json in Resources" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q "enable_user_learning.*false" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "appGroupIdentifier" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "fallbackAppGroupIdentifier" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "importRimeLexicons" platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
grep -q "maxRimeSourceBytes = 16 \* 1024 \* 1024" platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
grep -q "ime_engine_import_rime_lexicon" platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
grep -q "IosLexiconImportBridge.swift in Sources" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
grep -q 'URLSessionConfiguration.ephemeral' platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
grep -q 'reviewedRimeIceVersion = "2026.03.26"' platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
grep -q 'integrityCheckFailed' platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
grep -q 'response.url?.host == "raw.githubusercontent.com"' platform/ios_keyboard/ContainerApp/IosLexiconImportBridge.swift
grep -q 'importedLexiconSummaryText' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q 'imported_lexicon_manifest.json' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
if grep -q "import PrivatePinyinC" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift; then
  echo "Pure iOS settings and text conversion must not depend on the C bridge." >&2
  exit 1
fi
grep -q "ime_engine_new(pathPointer)" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
if grep -q "ime_engine_import_rime_lexicon\|processPendingRimeLexicons" \
  platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift; then
  echo "The iOS keyboard extension must remain a read-only consumer of imported lexicons." >&2
  exit 1
fi
grep -q "ime_session_feed_key" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_commit_candidate" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_toggle_mode" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_set_candidate_page_size" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_engine_enable_local_ai" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "ime_session_set_secure_input" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "static let preferredCandidatePageSize = 9" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "private static let fallbackCandidatePageSize = 5" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "let candidatePageSize: Int" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "nineKeyDigit: Int32 = 102" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "pageUp: Int32 = 14" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "pageDown: Int32 = 15" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "output.mode == IME_MODE_ENGLISH" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
grep -q "let settingsPath = IosSettingsStore.ensureSettingsFile()" platform/ios_keyboard/KeyboardExtension/IosPinyinCoreBridge.swift
if grep -q "englishMode.toggle()" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift; then
  echo "iOS keyboard mode UI must derive from C ABI output mode." >&2
  exit 1
fi
grep -q "candidateButtons" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "rowHorizontalInset" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "widthWeight" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "togglePreferences" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "setPredictionEnabled" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "clearLearningData" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "makeNineKeyGrid" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "makeNineKeyNumberGrid" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "nineKeyNumbersVisible" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "NineKeyPunctuationPopupView" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "UILongPressGestureRecognizer" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "insertQuickPunctuation" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "selectKeyboardLayout(.nineKey)" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "上一组候选" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "下一组候选" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "展开全部候选" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "private-pinyin-expanded-candidates" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "private-pinyin-expanded-candidate-" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "func toggleExpandedCandidates" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "func ensureCore()" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "var activationEvent: UIControl.Event" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "return .touchDown" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "return .touchUpInside" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q '.nineKeyDigit(4, letters: "GHI")' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q '.nineKeyDigit(7, letters: "PQRS")' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'needsInputModeSwitchKey ? .globe : .qwertyLayout' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'makeAdaptiveKeyRow' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'traitCollection.verticalSizeClass == .compact' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'static let nineKeyMoreSymbols' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'static let nineKeyNumbers' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'static let nineKeyLetters' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'static let nineKeyExtendedSymbols' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'static let candidateNextPage' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'title: "候选"' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'consumePendingSelfTextChangeCallback' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'selfTextChangeCallbackWindow: TimeInterval = 0.25' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'pendingSelfTextChangeDocumentIdentifier' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'textDocumentProxy.documentIdentifier' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'layoutSegmentedControl = UISegmentedControl(items: \["全键", "九宫"\])' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'StationKeyboardTheme' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'StationKeyButton' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'static let accent = UIColor(hex: 0xE8804A)' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'systemImageName: "ellipsis"' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'title = englishMode ? "space" : "猫栈拼音"' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'CandidateScrollView' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'touchesShouldCancel' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'UISelectionFeedbackGenerator' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'hitTestOutsets.left = 10' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'var displayedPreedit: String' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -Fq 'currentCandidates.first?.pinyin' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'title = "回车"' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'scriptSegmentedControl = UISegmentedControl(items: \["简体", "繁體"\])' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'IosChineseTextConverter.convert(text, to: chineseScript)' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'settings\["ios_chinese_script"\] = IosChineseScript.simplified.rawValue' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q 'ios_keyboard_layout_updated_at' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q 'ios_chinese_script_updated_at' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q 'readStoredSettings' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q '"Simplified-Traditional" as CFString' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q '系统通用繁体，非完整台港本地化' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q '裡面頭髮發展乾嘛麵條' platform/ios_keyboard/Tests/ChineseTextConverterRegression.swift
if grep -q '"换行"' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift; then
  echo "The iOS Return key must use the generic 回车 label rather than implying newline-only behavior." >&2
  exit 1
fi
if grep -q 'microphoneButton' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift; then
  echo "iOS supplies dictation outside third-party keyboards; do not duplicate a non-functional microphone." >&2
  exit 1
fi
grep -q "ios_keyboard_layout" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "ios_chinese_script" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "keyboardLayoutDefaultsKey" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "chineseScriptDefaultsKey" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -Fq 'try data.write(to: settingsURL, options: [.atomic])' platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "keyboardCandidatePageSize = 9" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
if grep -q "visibleCandidateCount = 9" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift; then
  echo "iOS candidate page size must have one source of truth in IosPinyinCoreBridge." >&2
  exit 1
fi
if sed -n '/private func makeNineKeyGrid()/,/private func makeAdaptiveKeyRow/p' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift | grep -q 'equalToConstant: \(52\|113\)'; then
  echo "The iOS nine-key grid must adapt to compact-height layouts." >&2
  exit 1
fi
if sed -n '/case \.nineKeyPunctuation:/,/case \.space:/p' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift | grep -q 'symbolsVisible = true'; then
  echo "The iOS nine-key punctuation shortcut must not open the complete symbol keyboard." >&2
  exit 1
fi
sed -n '/private func makeNineKeyGrid()/,/private func makeAdaptiveKeyRow/p' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift | grep -q '\.modeToggle'
grep -q '左右滑动查看更多候选' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "extendedSymbolsVisible" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'title: "#+="' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -Fq '"【", "】", "{", "}", "#", "%", "^", "*", "+", "="' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -Fq '"_", "—", "\\", "|", "~", "《", "》", "$", "&", "·"' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "IME_KEY_NINE_KEY_DIGIT = 102" ffi/c_api.h
grep -q "ime_session_set_candidate_page_size" ffi/c_api.h
if sed -n '/func feedCharacter/,/func handleTextKey/p' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift | grep -q "rebuildKeyboard"; then
  echo "Character input must not rebuild the complete iOS keyboard." >&2
  exit 1
fi
grep -q "isKeyboardExtension" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "canEnableLearning" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "repairRuntimePathsIfNeeded" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "setPredictionEnabled" platform/ios_keyboard/ContainerApp/IosSettingsStore.swift
grep -q "../../../ffi/c_api.h" platform/ios_keyboard/PrivatePinyinC/module.modulemap
grep -q "crate-type = \\[\"cdylib\", \"staticlib\", \"rlib\"\\]" ffi/ime_ffi/Cargo.toml
grep -q "PrivatePinyinKeyboard.appex in Embed App Extensions" platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj
test "$(grep -c 'libprivate_pinyin_ime.a' platform/ios_keyboard/PrivatePinyin.xcodeproj/project.pbxproj)" -eq 4
grep -q "com.apple.keyboard-service" platform/ios_keyboard/KeyboardExtension/Info.plist
grep -q "猫栈拼音" platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q "NavigationStack" platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q "SettingsDestination" platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'title: "开始使用"' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'title: "隐私与学习"' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'title: "词库管理"' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'title: "关于猫栈拼音"' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q "UIApplication.openSettingsURLString" platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q '\.fileImporter(' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q 'allowedContentTypes: rimeDocumentTypes' platform/ios_keyboard/ContainerApp/ContentView.swift
grep -q '"本地导入词库"' platform/ios_keyboard/ContainerApp/ContentView.swift
if grep -q "App-Prefs" platform/ios_keyboard/ContainerApp/ContentView.swift; then
  echo "iOS onboarding must use the public Settings URL, not App-Prefs." >&2
  exit 1
fi
grep -A1 "CFBundleDisplayName" platform/ios_keyboard/ContainerApp/Info.plist | grep -q "猫栈拼音"
grep -A1 "CFBundleDisplayName" platform/ios_keyboard/KeyboardExtension/Info.plist | grep -q "猫栈拼音"
if grep -nE '"(PrivatePinyin|Keyboard|Privacy|Enable PrivatePinyin|Full Access|User learning|Learn selected candidates|Clear Local Lexicon)' \
  platform/ios_keyboard/ContainerApp/ContentView.swift; then
  echo "iOS container app user-facing copy must remain Chinese." >&2
  exit 1
fi

network_pattern="URLSession|NWConnection|Network.framework|http://|https://"
if command -v rg >/dev/null 2>&1; then
  if rg -n "$network_pattern" \
    --glob "*.swift" \
    platform/ios_keyboard/KeyboardExtension; then
    echo "The iOS keyboard extension must not include network APIs or URLs." >&2
    exit 1
  fi
  if rg -n "$network_pattern" \
    --glob "*.swift" \
    --glob "!IosLexiconImportBridge.swift" \
    platform/ios_keyboard/ContainerApp; then
    echo "Container networking must stay isolated in IosLexiconImportBridge.swift." >&2
    exit 1
  fi
else
  found_network_api=0
  while IFS= read -r -d '' swift_file; do
    if grep -nE "$network_pattern" "$swift_file"; then
      found_network_api=1
    fi
  done < <(find platform/ios_keyboard/KeyboardExtension -name "*.swift" -print0)

  if [ "$found_network_api" -eq 1 ]; then
    echo "The iOS keyboard extension must not include network APIs or URLs." >&2
    exit 1
  fi

  found_network_api=0
  while IFS= read -r -d '' swift_file; do
    if grep -nE "$network_pattern" "$swift_file"; then
      found_network_api=1
    fi
  done < <(find platform/ios_keyboard/ContainerApp -name "*.swift" \
    ! -name "IosLexiconImportBridge.swift" -print0)

  if [ "$found_network_api" -eq 1 ]; then
    echo "Container networking must stay isolated in IosLexiconImportBridge.swift." >&2
    exit 1
  fi
fi

if command -v xcodebuild >/dev/null 2>&1; then
  mkdir -p build/ios_keyboard_xcode_home
  HOME="$PWD/build/ios_keyboard_xcode_home" \
    xcodebuild -list -project platform/ios_keyboard/PrivatePinyin.xcodeproj >/dev/null 2>&1
fi
