import UIKit

final class KeyboardViewController: UIInputViewController {
    private var core = IosPinyinCoreBridge()
    private let rootStack = UIStackView()
    private let candidateBar = UIStackView()
    private let candidateStack = UIStackView()
    private let keyRowsStack = UIStackView()
    private let preferencesView = UIView()
    private let preeditLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let predictionSwitch = UISwitch()
    private let learningSwitch = UISwitch()
    private let preferencesStatusLabel = UILabel()
    private var candidateButtons: [UIButton] = []
    private weak var shiftButton: UIButton?
    private weak var modeButton: UIButton?
    private var currentPreedit = ""
    private var currentCandidates: [IosPinyinCandidate] = []
    private var shifted = false
    private var symbolsVisible = false
    private var englishMode = false
    private var preferredLayout = IosSettingsStore.keyboardLayout()
    private var preferencesVisible = false
    private var isPerformingTextOperation = false
    private var lastNeedsInputModeSwitchKey = true

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        rebuildKeyboard()
        updateCandidateBar()
        refreshPreferenceControls()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        if isPerformingTextOperation {
            return
        }

        if let output = core?.reset() {
            englishMode = output.isEnglishMode
        }
        currentPreedit = ""
        currentCandidates = []
        refreshKeyStates()
        updateCandidateBar()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if lastNeedsInputModeSwitchKey != needsInputModeSwitchKey {
            lastNeedsInputModeSwitchKey = needsInputModeSwitchKey
            rebuildKeyboard()
        }
    }

    private func setupView() {
        view.backgroundColor = UIColor.systemGray5

        rootStack.axis = .vertical
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        setupCandidateBar()

        keyRowsStack.axis = .vertical
        keyRowsStack.distribution = .fillEqually
        keyRowsStack.spacing = 6
        rootStack.addArrangedSubview(keyRowsStack)

        setupPreferencesView()
        preferencesView.isHidden = true
        rootStack.addArrangedSubview(preferencesView)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 252),
            candidateBar.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    private func setupCandidateBar() {
        candidateBar.axis = .horizontal
        candidateBar.alignment = .fill
        candidateBar.spacing = 6
        rootStack.addArrangedSubview(candidateBar)

        candidateStack.axis = .horizontal
        candidateStack.alignment = .fill
        candidateStack.distribution = .fillEqually
        candidateStack.spacing = 6
        candidateBar.addArrangedSubview(candidateStack)

        configurePreeditLabel()
        candidateStack.addArrangedSubview(preeditLabel)

        for index in 0..<5 {
            let button = makeCandidateButton(index: index)
            button.isHidden = true
            candidateButtons.append(button)
            candidateStack.addArrangedSubview(button)
        }

        settingsButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        settingsButton.tintColor = .secondaryLabel
        settingsButton.backgroundColor = UIColor.systemGray4
        settingsButton.layer.cornerRadius = 6
        settingsButton.accessibilityLabel = "键盘偏好设置"
        settingsButton.addAction(UIAction { [weak self] _ in
            self?.togglePreferences()
        }, for: .touchUpInside)
        settingsButton.widthAnchor.constraint(equalToConstant: 38).isActive = true
        candidateBar.addArrangedSubview(settingsButton)
    }

    private func configurePreeditLabel() {
        preeditLabel.textAlignment = .center
        preeditLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        preeditLabel.textColor = .secondaryLabel
        preeditLabel.backgroundColor = UIColor.systemGray6
        preeditLabel.layer.cornerRadius = 6
        preeditLabel.layer.masksToBounds = true
        preeditLabel.adjustsFontSizeToFitWidth = true
        preeditLabel.minimumScaleFactor = 0.72
    }

    private func makeCandidateButton(index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.72
        button.backgroundColor = UIColor.systemBackground
        button.layer.cornerRadius = 6
        button.setTitleColor(.label, for: .normal)
        button.addAction(UIAction { [weak self] _ in
            self?.commitCandidate(index)
        }, for: .touchUpInside)
        return button
    }

    private func setupPreferencesView() {
        preferencesView.backgroundColor = UIColor.systemGray6
        preferencesView.layer.cornerRadius = 8

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        preferencesView.addSubview(stack)

        predictionSwitch.onTintColor = UIColor.systemYellow
        predictionSwitch.accessibilityLabel = "显示预测候选"
        predictionSwitch.addAction(UIAction { [weak self] _ in
            self?.setPredictionEnabled()
        }, for: .valueChanged)

        learningSwitch.onTintColor = UIColor.systemYellow
        learningSwitch.accessibilityLabel = "记住我常选的词"
        learningSwitch.addAction(UIAction { [weak self] _ in
            self?.setLearningEnabled()
        }, for: .valueChanged)

        stack.addArrangedSubview(makePreferenceRow(
            title: "显示预测候选",
            detail: "提交后显示下一词建议",
            toggle: predictionSwitch
        ))
        stack.addArrangedSubview(makeDivider())
        stack.addArrangedSubview(makePreferenceRow(
            title: "记住我常选的词",
            detail: "学习记录只保存在本机",
            toggle: learningSwitch
        ))
        stack.addArrangedSubview(makeDivider())
        stack.addArrangedSubview(makePreferenceFooter())

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: preferencesView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: preferencesView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: preferencesView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: preferencesView.bottomAnchor),
        ])
    }

    private func makePreferenceRow(title: String, detail: String, toggle: UISwitch) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabel

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 2

        let row = UIStackView(arrangedSubviews: [labels, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        return row
    }

    private func makePreferenceFooter() -> UIView {
        preferencesStatusLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        preferencesStatusLabel.textColor = .secondaryLabel
        preferencesStatusLabel.numberOfLines = 2
        preferencesStatusLabel.adjustsFontSizeToFitWidth = true
        preferencesStatusLabel.minimumScaleFactor = 0.75

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("清除", for: .normal)
        clearButton.setImage(UIImage(systemName: "trash"), for: .normal)
        clearButton.tintColor = .systemRed
        clearButton.setTitleColor(.systemRed, for: .normal)
        clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        clearButton.accessibilityLabel = "清除本机学习记录"
        clearButton.addAction(UIAction { [weak self] _ in
            self?.clearLearningData()
        }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [preferencesStatusLabel, clearButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        return row
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = UIColor.separator
        divider.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale).isActive = true
        return divider
    }

    private func rebuildKeyboard() {
        keyRowsStack.arrangedSubviews.forEach { view in
            keyRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        shiftButton = nil
        modeButton = nil

        let rows: [[KeySpec]]
        if symbolsVisible {
            rows = symbolRows()
        } else if usesNineKeyLayout {
            rows = nineKeyRows()
        } else {
            rows = letterRows()
        }
        for (rowIndex, row) in rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fill
            rowStack.spacing = 6

            let horizontalInset = rowHorizontalInset(at: rowIndex)
            if horizontalInset > 0 {
                rowStack.isLayoutMarginsRelativeArrangement = true
                rowStack.layoutMargins = UIEdgeInsets(
                    top: 0,
                    left: horizontalInset,
                    bottom: 0,
                    right: horizontalInset
                )
            }

            var weightedButtons: [(button: UIButton, weight: CGFloat)] = []
            for key in row {
                let button = makeKeyButton(key)
                rowStack.addArrangedSubview(button)
                weightedButtons.append((button, key.widthWeight))
            }

            if let reference = weightedButtons.first {
                for item in weightedButtons.dropFirst() {
                    item.button.widthAnchor.constraint(
                        equalTo: reference.button.widthAnchor,
                        multiplier: item.weight / reference.weight
                    ).isActive = true
                }
            }
            keyRowsStack.addArrangedSubview(rowStack)
        }
        refreshKeyStates()
    }

    private func rowHorizontalInset(at index: Int) -> CGFloat {
        guard !usesNineKeyLayout, index == 1 else {
            return 0
        }
        return symbolsVisible ? 14 : 16
    }

    private func letterRows() -> [[KeySpec]] {
        [
            "qwertyuiop".map { .character(String($0)) },
            "asdfghjkl".map { .character(String($0)) },
            [.shift] + "zxcvbnm".map { .character(String($0)) } + [.backspace],
            qwertyCommandRow(),
        ]
    }

    private func nineKeyRows() -> [[KeySpec]] {
        [
            [.nineKeyPunctuation, .nineKeyDigit(2, letters: "ABC"),
             .nineKeyDigit(3, letters: "DEF"), .backspace],
            [.nineKeyDigit(4, letters: "GHI"), .nineKeyDigit(5, letters: "JKL"),
             .nineKeyDigit(6, letters: "MNO"), .nineKeySpace],
            [.nineKeyDigit(7, letters: "PQRS"), .nineKeyDigit(8, letters: "TUV"),
             .nineKeyDigit(9, letters: "WXYZ"), .enter],
            nineKeyCommandRow(),
        ]
    }

    private func symbolRows() -> [[KeySpec]] {
        [
            "1234567890".map { .text(String($0)) },
            [".", ",", "?", "!", "'", "-", ":", ";", "/"].map { .text($0) },
            [.text("("), .text(")"), .text("@"), .text("#"), .text("$"), .text("&"), .backspace],
            commandRow(with: preferredLayout == .nineKey && !englishMode ? .nineKeyLayout : .letters),
        ]
    }

    private func qwertyCommandRow() -> [KeySpec] {
        var row = commandRow(with: .symbols)
        if !englishMode {
            row.insert(.nineKeyLayout, at: needsInputModeSwitchKey ? 2 : 1)
        }
        return row
    }

    private func nineKeyCommandRow() -> [KeySpec] {
        var row: [KeySpec] = []
        if needsInputModeSwitchKey {
            row.append(.globe)
        }
        row.append(contentsOf: [.symbols, .letters, .modeToggle])
        return row
    }

    private func commandRow(with layoutToggle: KeySpec) -> [KeySpec] {
        var row: [KeySpec] = []
        if needsInputModeSwitchKey {
            row.append(.globe)
        }
        row.append(contentsOf: [layoutToggle, .space, .modeToggle, .enter])
        return row
    }

    private func makeKeyButton(_ key: KeySpec) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(key.title, for: .normal)
        if let systemImageName = key.systemImageName {
            button.setImage(UIImage(systemName: systemImageName), for: .normal)
        }
        button.accessibilityLabel = key.accessibilityLabel
        button.titleLabel?.font = UIFont.systemFont(ofSize: key.isWide ? 15 : 18, weight: .medium)
        button.titleLabel?.numberOfLines = key.title?.contains("\n") == true ? 2 : 1
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.backgroundColor = key.isCommand ? UIColor.systemGray3 : UIColor.systemBackground
        button.layer.cornerRadius = 6
        button.layer.cornerCurve = .continuous
        button.tintColor = .label
        button.setTitleColor(.label, for: .normal)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.handle(key)
        }, for: .touchUpInside)

        switch key.kind {
        case .shift:
            shiftButton = button
        case .modeToggle:
            modeButton = button
        default:
            break
        }
        return button
    }

    private func refreshKeyStates() {
        shiftButton?.backgroundColor = shifted ? UIColor.systemYellow : UIColor.systemGray3
        shiftButton?.tintColor = shifted ? UIColor.black : UIColor.label
        modeButton?.setTitle(englishMode ? "EN" : "中", for: .normal)
    }

    private func updateCandidateBar() {
        if preferencesVisible {
            preeditLabel.text = "键盘偏好设置"
            preeditLabel.isHidden = false
            candidateButtons.forEach { button in
                button.setTitle(nil, for: .normal)
                button.isHidden = true
            }
            settingsButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            settingsButton.isEnabled = true
            return
        }

        settingsButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        settingsButton.isEnabled = currentPreedit.isEmpty
        settingsButton.alpha = settingsButton.isEnabled ? 1.0 : 0.45

        let showPreedit = !currentPreedit.isEmpty || currentCandidates.isEmpty
        preeditLabel.text = currentPreedit
        preeditLabel.isHidden = !showPreedit

        for (index, button) in candidateButtons.enumerated() {
            guard index < currentCandidates.count else {
                button.setTitle(nil, for: .normal)
                button.isHidden = true
                continue
            }
            button.setTitle(currentCandidates[index].text, for: .normal)
            button.accessibilityLabel = "候选词 \(currentCandidates[index].text)"
            button.isHidden = false
        }
    }

    private func handle(_ key: KeySpec) {
        switch key.kind {
        case .character(let value):
            feedCharacter(value)
        case .text(let value):
            handleTextKey(value)
        case .nineKeyDigit(let value):
            apply(core?.feed(keyCode: IosKeyCodeValue.nineKeyDigit, text: value))
        case .nineKeyPunctuation:
            applyOrInsert(core?.feed(keyCode: IosKeyCodeValue.comma, text: ","), fallback: "，")
        case .space:
            applyOrInsert(core?.feed(keyCode: IosKeyCodeValue.space, text: " "), fallback: " ")
        case .enter:
            applyOrInsert(core?.feed(keyCode: IosKeyCodeValue.enter, text: "\n"), fallback: "\n")
        case .backspace:
            handleBackspace()
        case .shift:
            shifted.toggle()
            refreshKeyStates()
        case .globe:
            advanceToNextInputMode()
        case .symbols:
            symbolsVisible = true
            rebuildKeyboard()
        case .letters:
            symbolsVisible = false
            selectKeyboardLayout(.qwerty)
        case .nineKeyLayout:
            symbolsVisible = false
            selectKeyboardLayout(.nineKey)
        case .modeToggle:
            apply(core?.toggleMode())
        }
    }
}

private extension KeyboardViewController {
    func feedCharacter(_ value: String) {
        let wasShifted = shifted
        defer {
            if wasShifted {
                shifted = false
                refreshKeyStates()
            }
        }

        if wasShifted && !englishMode {
            endActiveInputIfNeeded()
            insertDocumentText(value.uppercased())
            return
        }

        let text = wasShifted ? value.uppercased() : value
        let output = core?.feed(
            keyCode: IosKeyCodeValue.character,
            text: text,
            shift: wasShifted
        )
        apply(output)
    }

    func handleTextKey(_ value: String) {
        if let keyCode = coreKeyCode(for: value) {
            applyOrInsert(core?.feed(keyCode: keyCode, text: value), fallback: value)
            return
        }

        endActiveInputIfNeeded()
        insertDocumentText(value)
    }

    func handleBackspace() {
        if hasActiveInput {
            apply(core?.feed(keyCode: IosKeyCodeValue.backspace))
        } else {
            deleteDocumentBackward()
        }
    }

    func commitCandidate(_ index: Int) {
        apply(core?.commitCandidate(index: index))
    }

    func applyOrInsert(_ output: IosPinyinOutput?, fallback: String) {
        let previousActiveInput = hasActiveInput
        apply(output)
        if !previousActiveInput && output?.shouldCommit != true {
            insertDocumentText(fallback)
        }
    }

    func endActiveInputIfNeeded() {
        if hasActiveInput {
            apply(core?.feed(keyCode: IosKeyCodeValue.enter, text: "\n"))
        }
    }

    func apply(_ output: IosPinyinOutput?) {
        guard let output else {
            return
        }

        let modeChanged = englishMode != output.isEnglishMode
        englishMode = output.isEnglishMode

        if output.shouldCommit, !output.commitText.isEmpty {
            insertDocumentText(output.commitText)
        }

        currentPreedit = output.preedit
        currentCandidates = output.shouldShowCandidates ? output.candidates : []
        if modeChanged {
            symbolsVisible = false
            rebuildKeyboard()
        }
        updateCandidateBar()
    }

    var hasActiveInput: Bool {
        !currentPreedit.isEmpty || !currentCandidates.isEmpty
    }

    func insertDocumentText(_ text: String) {
        performTextOperation {
            textDocumentProxy.insertText(text)
        }
    }

    func deleteDocumentBackward() {
        performTextOperation {
            textDocumentProxy.deleteBackward()
        }
    }

    func performTextOperation(_ operation: () -> Void) {
        isPerformingTextOperation = true
        defer {
            isPerformingTextOperation = false
        }
        operation()
    }

    func coreKeyCode(for value: String) -> Int32? {
        switch value {
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return IosKeyCodeValue.digit
        case ",":
            return IosKeyCodeValue.comma
        case ".":
            return IosKeyCodeValue.period
        case "-":
            return IosKeyCodeValue.minus
        case "=":
            return IosKeyCodeValue.equal
        case "'":
            return IosKeyCodeValue.apostrophe
        case ";":
            return IosKeyCodeValue.semicolon
        default:
            return nil
        }
    }

    var usesNineKeyLayout: Bool {
        preferredLayout == .nineKey && !englishMode && !symbolsVisible
    }

    func selectKeyboardLayout(_ layout: IosKeyboardLayout) {
        guard preferredLayout != layout else {
            rebuildKeyboard()
            return
        }

        if hasActiveInput {
            apply(core?.reset())
        }
        preferredLayout = layout
        _ = IosSettingsStore.setKeyboardLayout(layout)
        rebuildKeyboard()
    }
}

private extension KeyboardViewController {
    func togglePreferences() {
        guard currentPreedit.isEmpty else {
            return
        }
        preferencesVisible.toggle()
        keyRowsStack.isHidden = preferencesVisible
        preferencesView.isHidden = !preferencesVisible
        if preferencesVisible {
            currentCandidates = []
            refreshPreferenceControls()
        }
        updateCandidateBar()
    }

    func refreshPreferenceControls() {
        predictionSwitch.isOn = IosSettingsStore.isPredictionEnabled()
        learningSwitch.isOn = IosSettingsStore.isLearningEnabled()
        learningSwitch.isEnabled = IosSettingsStore.canEnableLearning
        preferencesStatusLabel.text = IosSettingsStore.keyboardStorageDescription(
            hasFullAccess: hasFullAccess
        )
    }

    func setPredictionEnabled() {
        guard IosSettingsStore.setPredictionEnabled(predictionSwitch.isOn) else {
            predictionSwitch.isOn = IosSettingsStore.isPredictionEnabled()
            preferencesStatusLabel.text = "无法保存预测设置"
            return
        }
        reloadCoreAfterSettingsChange(status: "预测设置已保存")
    }

    func setLearningEnabled() {
        guard IosSettingsStore.setLearningEnabled(learningSwitch.isOn) else {
            learningSwitch.isOn = IosSettingsStore.isLearningEnabled()
            preferencesStatusLabel.text = "当前环境无法启用用户学习"
            return
        }
        reloadCoreAfterSettingsChange(status: learningSwitch.isOn ? "用户学习已开启" : "用户学习已关闭")
    }

    func clearLearningData() {
        core = nil
        do {
            let removed = try IosSettingsStore.clearLocalLexiconArtifacts()
            core = IosPinyinCoreBridge()
            clearCompositionState()
            preferencesStatusLabel.text = removed == 0 ? "没有本机学习记录" : "本机学习记录已清除"
        } catch {
            core = IosPinyinCoreBridge()
            preferencesStatusLabel.text = "无法清除本机学习记录"
        }
    }

    func reloadCoreAfterSettingsChange(status: String) {
        core = IosPinyinCoreBridge()
        clearCompositionState()
        preferencesStatusLabel.text = core == nil ? "输入引擎重新载入失败" : status
    }

    func clearCompositionState() {
        currentPreedit = ""
        currentCandidates = []
        updateCandidateBar()
    }
}

private struct KeySpec {
    enum Kind {
        case character(String)
        case text(String)
        case nineKeyDigit(String)
        case nineKeyPunctuation
        case space
        case enter
        case backspace
        case shift
        case globe
        case symbols
        case letters
        case nineKeyLayout
        case modeToggle
    }

    let kind: Kind
    let title: String?
    let systemImageName: String?
    let accessibilityLabel: String
    let isCommand: Bool
    let isWide: Bool
    let widthWeight: CGFloat

    static func character(_ value: String) -> Self {
        Self(
            kind: .character(value),
            title: value.uppercased(),
            systemImageName: nil,
            accessibilityLabel: value.uppercased(),
            isCommand: false,
            isWide: false,
            widthWeight: 1
        )
    }

    static func text(_ value: String) -> Self {
        Self(
            kind: .text(value),
            title: value,
            systemImageName: nil,
            accessibilityLabel: value,
            isCommand: false,
            isWide: false,
            widthWeight: 1
        )
    }

    static func nineKeyDigit(_ value: Int, letters: String) -> Self {
        Self(
            kind: .nineKeyDigit(String(value)),
            title: "\(value)\n\(letters)",
            systemImageName: nil,
            accessibilityLabel: "九宫格 \(value) \(letters)",
            isCommand: false,
            isWide: false,
            widthWeight: 1
        )
    }

    static let nineKeyPunctuation = Self(
        kind: .nineKeyPunctuation,
        title: "1\n，",
        systemImageName: nil,
        accessibilityLabel: "中文逗号",
        isCommand: false,
        isWide: false,
        widthWeight: 1
    )

    static let shift = Self(
        kind: .shift,
        title: nil,
        systemImageName: "shift",
        accessibilityLabel: "大写",
        isCommand: true,
        isWide: true,
        widthWeight: 1.35
    )
    static let backspace = Self(
        kind: .backspace,
        title: nil,
        systemImageName: "delete.left",
        accessibilityLabel: "删除",
        isCommand: true,
        isWide: true,
        widthWeight: 1.35
    )
    static let globe = Self(
        kind: .globe,
        title: nil,
        systemImageName: "globe",
        accessibilityLabel: "切换输入法",
        isCommand: true,
        isWide: true,
        widthWeight: 0.9
    )
    static let symbols = Self(
        kind: .symbols,
        title: "123",
        systemImageName: nil,
        accessibilityLabel: "数字与符号",
        isCommand: true,
        isWide: true,
        widthWeight: 1.2
    )
    static let letters = Self(
        kind: .letters,
        title: "ABC",
        systemImageName: nil,
        accessibilityLabel: "字母",
        isCommand: true,
        isWide: true,
        widthWeight: 1.2
    )
    static let nineKeyLayout = Self(
        kind: .nineKeyLayout,
        title: "九宫",
        systemImageName: nil,
        accessibilityLabel: "切换到九宫格拼音",
        isCommand: true,
        isWide: true,
        widthWeight: 1.2
    )
    static let space = Self(
        kind: .space,
        title: "空格",
        systemImageName: nil,
        accessibilityLabel: "空格",
        isCommand: false,
        isWide: true,
        widthWeight: 3.15
    )
    static let nineKeySpace = Self(
        kind: .space,
        title: "空格",
        systemImageName: nil,
        accessibilityLabel: "空格",
        isCommand: true,
        isWide: true,
        widthWeight: 1.35
    )
    static let enter = Self(
        kind: .enter,
        title: nil,
        systemImageName: "return",
        accessibilityLabel: "换行",
        isCommand: true,
        isWide: true,
        widthWeight: 1.2
    )
    static let modeToggle = Self(
        kind: .modeToggle,
        title: "中",
        systemImageName: nil,
        accessibilityLabel: "中英文切换",
        isCommand: true,
        isWide: true,
        widthWeight: 1.15
    )
}
