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
grep -q "func startCoreLoadIfNeeded()" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "func enqueueCoreOperation(" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "func scheduleCoreOperation(" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "coreOperationQueue.async" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "coreInteractionRevision" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "override func textDidChange" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "override func viewDidAppear" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "override func viewWillDisappear" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "keyboardSurfaceFrozen = true" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "keyboardSurfaceFrozen = false" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "resumeKeyboardSurfaceForDeliveredKeyIfPresented()" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "view.setNeedsLayout()" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "surfaceRefreshDeferred = true" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "func refreshKeyboardSurface(force: Bool = false)" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "idleCorePrewarmDelay: TimeInterval = 0.12" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "candidateCommitInFlight = false" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "guard !candidateCommitInFlight," platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "button.isEnabled = !candidateCommitInFlight" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "func finishCandidateCommit()" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
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
grep -q 'UISelectionFeedbackGenerator(view: view)' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'UIImpactFeedbackGenerator(style: .light, view: view)' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'impactOccurred(intensity: 0.62)' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'expandOuterHitTargets' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'var displayedPreedit: String' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -Fq 'currentCandidates.first?.pinyin' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -Fq '"2": "ABC"' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -Fq 'joined(separator: " ")' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
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
python3 - <<'PY'
from pathlib import Path
from tempfile import TemporaryDirectory


def function_body(path: str, marker: str) -> str:
    source = Path(path).read_text(encoding="utf-8")
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"iOS source contract missing function marker {marker!r} in {path}")
    opening = source.find("{", start)
    if opening < 0:
        raise SystemExit(f"iOS source contract missing opening brace for {marker!r} in {path}")

    def skip_quoted(index: int, delimiter: str) -> int:
        index += len(delimiter)
        while index < len(source):
            if source.startswith(delimiter, index):
                return index + len(delimiter)
            if source[index] == "\\" and len(delimiter) == 1:
                index += 2
            else:
                index += 1
        raise SystemExit(f"iOS source contract found an unterminated string in {path}")

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
        raise SystemExit(f"iOS source contract found an unterminated block comment in {path}")

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
            raise SystemExit(f"iOS source contract found an unterminated raw string in {path}")
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
    raise SystemExit(f"iOS source contract missing closing brace for {marker!r} in {path}")


def require(body: str, token: str, label: str) -> None:
    if token not in body:
        raise SystemExit(f"iOS source contract missing {label}: {token!r}")


def forbid(body: str, token: str, label: str) -> None:
    if token in body:
        raise SystemExit(f"iOS source contract forbids {label}: {token!r}")


with TemporaryDirectory() as directory:
    parser_probe = Path(directory) / "parser_probe.swift"
    parser_probe.write_text(
        '''
func parserProbe() {
    let quoted = "}"
    let multiline = """
    }
    """
    // }
    /* } /* { */ } */
    parserReachedRealEnd()
}
''',
        encoding="utf-8",
    )
    require(
        function_body(str(parser_probe), "func parserProbe"),
        "parserReachedRealEnd()",
        "string/comment-aware function-body parsing",
    )

source = Path(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift"
).read_text(encoding="utf-8")

nine_key_grid = source.split("    private func makeNineKeyGrid()", 1)[1].split(
    "    private func makeAdaptiveKeyRow", 1
)[0]
if "equalToConstant: 52" in nine_key_grid or "equalToConstant: 113" in nine_key_grid:
    raise SystemExit("The iOS nine-key grid must adapt to compact-height layouts.")
if ".modeToggle" not in nine_key_grid:
    raise SystemExit("The iOS nine-key grid must retain the Chinese/English toggle.")

feed_character = source.split("    func feedCharacter", 1)[1].split(
    "    func handleTextKey", 1
)[0]
if "rebuildKeyboard" in feed_character:
    raise SystemExit("Character input must not rebuild the complete iOS keyboard.")

keyboard_rebuild = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "private func rebuildKeyboardContents()",
)
for contract in (
    "let horizontalInset = rowHorizontalInset(at: rowIndex)",
    "left: horizontalInset",
    "right: horizontalInset",
    "expandOuterHitTargets(",
    "intoHorizontalMargin: horizontalInset",
):
    require(
        keyboard_rebuild,
        contract,
        "one shared horizontal inset for layout and outer hit targets",
    )

edge_hit_targets = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "private func expandOuterHitTargets(",
)
for contract in (
    "hitTestOutsets.left = horizontalInset",
    "hitTestOutsets.right = horizontalInset",
):
    require(edge_hit_targets, contract, "both inset-row outer margins remaining tappable")

make_key_button = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "private func makeKeyButton(",
)
for legacy_contract in (
    "hitTestOutsets.left = 10",
    "hitTestOutsets.right = 10",
    'value == "a"',
    'value == "l"',
):
    forbid(
        make_key_button,
        legacy_contract,
        "letter-specific edge-hit behavior in makeKeyButton",
    )

view_did_load = source.split("    override func viewDidLoad()", 1)[1].split(
    "    override func textWillChange", 1
)[0]
if "lastNeedsInputModeSwitchKey = needsInputModeSwitchKey" not in view_did_load:
    raise SystemExit("The iOS keyboard must seed its input-mode-switch state before layout.")
if "startCoreLoadIfNeeded()" not in view_did_load:
    raise SystemExit("The iOS keyboard must start background core prewarming after building UI.")
if "IosPinyinCoreBridge()" in view_did_load:
    raise SystemExit("Lexicon initialization must not run synchronously during presentation.")

text_will_change = source.split("    override func textWillChange", 1)[1].split(
    "    override func textDidChange", 1
)[0]
if "super.textWillChange(textInput)" not in text_will_change:
    raise SystemExit("The iOS document-change lifecycle must call super.textWillChange.")
if "keyboardSurfaceFrozen = true" not in text_will_change:
    raise SystemExit("External iOS document changes must freeze the surface before queued reset work.")
if "disableFrozenCandidateControls()" not in text_will_change:
    raise SystemExit("Frozen iOS document changes must visibly disable stale candidate controls.")

disable_frozen_candidates = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "private func disableFrozenCandidateControls()",
)
for required in (
    "candidateButtons + expandedCandidateButtons",
    "button.isEnabled = false",
    "expandCandidateButton.isEnabled = false",
):
    require(
        disable_frozen_candidates,
        required,
        "noninteractive frozen iOS candidate controls",
    )

text_did_change = source.split("    override func textDidChange", 1)[1].split(
    "    override func viewWillAppear", 1
)[0]
for forbidden in (
    "resumeKeyboardSurface",
    "DispatchQueue.main.asyncAfter",
    "refreshKeyboardSurface",
):
    if forbidden in text_did_change:
        raise SystemExit(
            "Document completion must not guess at host dismissal timing or thaw geometry: "
            f"{forbidden}"
        )
if "visibleDocumentChangeThawDelay" in source:
    raise SystemExit("The iOS host-dismissal boundary must not use a timed thaw heuristic.")

view_did_appear = source.split("    override func viewDidAppear", 1)[1].split(
    "    override func viewWillDisappear", 1
)[0]
if "resumeKeyboardSurfaceIfNeeded()" not in view_did_appear:
    raise SystemExit("Warm iOS keyboard reuse must thaw again from viewDidAppear.")

key_handler = source.split("    private func handle(_ key: KeySpec)", 1)[1].split(
    "    @objc private func handleQuickPunctuationGesture", 1
)[0]
if "resumeKeyboardSurfaceForDeliveredKeyIfPresented()" not in key_handler:
    raise SystemExit("A delivered iOS key event must use the presentation-gated thaw path.")

if "resumeKeyboardSurfaceAfterDocumentChangeIfStillVisible" in source:
    raise SystemExit("Document callbacks must not reintroduce an automatic surface thaw.")

key_surface_resume = source.split(
    "    private func resumeKeyboardSurfaceForDeliveredKeyIfPresented", 1
)[1].split("    func selectKeyboardLayout", 1)[0]
for required in (
    "keyboardPresentationPhase == .appearing",
    "keyboardPresentationPhase == .visible",
    "viewIfLoaded?.window != nil",
    "resumeKeyboardSurfaceIfNeeded()",
):
    if required not in key_surface_resume:
        raise SystemExit(f"Missing presentation-gated iOS key thaw contract: {required}")

if "previousCandidatePageButton" in source or "nextCandidatePageButton" in source:
    raise SystemExit("The compact iOS candidate bar must use only the downward expansion entry.")
if "打开候选网格，可使用上一组和下一组按钮浏览" not in source:
    raise SystemExit("The compact iOS expansion control must expose accessible candidate paging guidance.")

surface_resume = source.split(
    "    private func resumeKeyboardSurfaceIfNeeded", 1
)[1].split("    func selectKeyboardLayout", 1)[0]
for required in (
    "keyboardSurfaceFrozen = false",
    "refreshKeyboardSurface(force: true)",
):
    if required not in surface_resume:
        raise SystemExit(f"Missing iOS keyboard thaw contract: {required}")

surface_refresh = source.split("    func refreshKeyboardSurface", 1)[1].split(
    "    private func resumeKeyboardSurfaceIfNeeded", 1
)[0]
if "view.setNeedsLayout()" not in surface_refresh:
    raise SystemExit("Resuming the iOS keyboard surface must request explicit layout recovery.")

core_loader = source.split("    func startCoreLoadIfNeeded()", 1)[1].split(
    "    func invalidateCore()", 1
)[0]
if "coreOperationQueue.async" not in core_loader or "DispatchQueue.main.async" not in core_loader:
    raise SystemExit("The iOS lexicon must load off-main and publish its session on main.")
if "pendingCoreOperations" not in core_loader:
    raise SystemExit("Early iOS key events must be replayed after background core loading.")

core_operations = source.split("    func scheduleCoreOperation(", 1)[1].split(
    "    func observeCoreLoad", 1
)[0]
if "coreOperationQueue.async" not in core_operations:
    raise SystemExit("Every iOS Rust core operation must execute off the main thread.")
if "core.setSecureInput" not in core_operations:
    raise SystemExit("Every queued iOS core operation must refresh secure-input state.")
if "pendingOperation.revision == self.coreInteractionRevision" not in core_operations:
    raise SystemExit("Stale iOS core results must be rejected after context changes.")
for required in (
    "pendingOperation.coalescesIntermediateOutput",
    "pendingOperation.outputSequence != self.coreOutputSequence",
    "output?.shouldCommit != true",
    "finishPendingCompositionTracking(for: pendingOperation)",
    'name: "CoreOutputCoalesced"',
):
    if required not in core_operations:
        raise SystemExit(f"Missing iOS intermediate-output coalescing contract: {required}")

perform_core_output = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func performCoreOutput(",
)
for required in (
    "coalescesIntermediateOutput && fallback == nil && afterApply == nil",
    "safelyCoalescesIntermediateOutput",
):
    require(
        perform_core_output,
        required,
        "fail-safe iOS intermediate-output coalescing eligibility",
    )

nine_key_feed = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func feedNineKeyDigit(",
)
require(
    nine_key_feed,
    "coalescesIntermediateOutput: true",
    "nine-key digit output coalescing",
)
require(
    nine_key_feed,
    "tracksPendingComposition: true",
    "nine-key pending-composition tracking",
)

full_key_feed = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func feedCharacter(",
)
require(
    full_key_feed,
    "performCoreOutput(tracksPendingComposition: true)",
    "full-key pending-composition tracking",
)

backspace_handler = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func handleBackspace()",
)
require(
    backspace_handler,
    "coalescesIntermediateOutput: usesNineKeyLayout",
    "nine-key Backspace output coalescing",
)
require(
    backspace_handler,
    "hasActiveInput || !pendingCompositionOperationIdentifiers.isEmpty",
    "in-flight composition protection for host-document Backspace",
)

candidate_bar = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "private func updateCandidateBar()",
)
for required in (
    'name: "UpdateCandidateBar"',
    "diagnosticCandidateBarUpdates += 1",
):
    require(candidate_bar, required, "iOS candidate-render measurement")

apply_output = function_body(
    "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
    "func apply(_ output:",
)
for required in (
    'name: "ApplyCoreOutput"',
    "diagnosticAppliedCoreOutputs += 1",
):
    require(apply_output, required, "iOS core-output apply measurement")

for feedback_marker in ("func provideSelectionFeedback()", "func provideTypingFeedback()"):
    feedback_body = function_body(
        "platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift",
        feedback_marker,
    )
    require(
        feedback_body,
        "guard hasFullAccess",
        "Full-Access gating for optional UIKit feedback",
    )

if "configuredCore()" in source:
    raise SystemExit("The iOS keyboard must not expose a synchronous main-thread core accessor.")
for forbidden in ("core?.feed(", "core?.reset(", "core?.commitCandidate("):
    if forbidden in source:
        raise SystemExit(f"iOS FFI operation escaped the serial worker queue: {forbidden}")

preferences_setup = source.split("    private func setupPreferencesView()", 1)[1].split(
    "    private func configurePreferenceSegmentedControl", 1
)[0]
if "guard !preferencesViewPrepared" not in preferences_setup:
    raise SystemExit("Inline preferences must be built lazily after keyboard presentation.")

rebuild_wrapper = source.split("    private func rebuildKeyboard()", 1)[1].split(
    "    private func rebuildKeyboardContents()", 1
)[0]
if "UIView.performWithoutAnimation" not in rebuild_wrapper:
    raise SystemExit("Complete keyboard rebuilds must not animate during host transitions.")
if "view.isOpaque = true" not in source or "trayGradient.isOpaque = true" not in source:
    raise SystemExit("The iOS keyboard root must remain opaque for smooth transitions.")

def case_body(case_name: str) -> str:
    marker = f"        case {case_name}:"
    if marker not in source:
        raise SystemExit(f"Missing Swift case contract: {case_name}")
    body = source.split(marker, 1)[1]
    return body.split("\n        case ", 1)[0]

punctuation_body = case_body(".nineKeyPunctuation")
if 'insertQuickPunctuation("，")' not in punctuation_body:
    raise SystemExit("The iOS nine-key punctuation shortcut must insert quick punctuation.")
if "symbolsVisible = true" in punctuation_body:
    raise SystemExit(
        "The iOS nine-key punctuation shortcut must not open the complete symbol keyboard."
    )

more_symbols = source.split("    static let nineKeyMoreSymbols", 1)[1].split(
    "    static let nineKeyExtendedSymbols", 1
)[0]
extended_symbols = source.split("    static let nineKeyExtendedSymbols", 1)[1].split(
    "    static let letters", 1
)[0]
if "kind: .symbols" not in more_symbols:
    raise SystemExit("The #@¥ key must open the primary symbol page.")
if "kind: .extendedSymbols" not in extended_symbols:
    raise SystemExit("The 更多 key must open the extended symbol page.")

number_grid = source.split("    private func makeNineKeyNumberGrid()", 1)[1].split(
    "    private func makeAdaptiveKeyRow", 1
)[0]
if "needsInputModeSwitchKey ? .globe : .qwertyLayout" not in number_grid:
    raise SystemExit("The nine-key number page must retain the required globe key.")
if "accessibilityCustomActions" not in source:
    raise SystemExit("Quick punctuation alternatives must be exposed to VoiceOver.")
PY
grep -q '轻点候选，或展开全部候选查看更多' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "extendedSymbolsVisible" platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q 'title: "#+="' platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -Fq '"【", "】", "{", "}", "#", "%", "^", "*", "+", "="' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -Fq '"_", "—", "\\", "|", "~", "《", "》", "$", "&", "·"' \
  platform/ios_keyboard/KeyboardExtension/KeyboardViewController.swift
grep -q "IME_KEY_NINE_KEY_DIGIT = 102" ffi/c_api.h
grep -q "ime_session_set_candidate_page_size" ffi/c_api.h
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
