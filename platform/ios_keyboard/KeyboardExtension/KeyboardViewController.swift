import UIKit

final class KeyboardViewController: UIInputViewController {
    private let core = IosPinyinCoreBridge()
    private let rootStack = UIStackView()
    private let candidateStack = UIStackView()
    private let keyRowsStack = UIStackView()
    private var currentPreedit = ""
    private var currentCandidates: [IosPinyinCandidate] = []
    private var shifted = false
    private var symbolsVisible = false
    private var englishMode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        rebuildKeyboard()
        updateCandidateBar()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        _ = core?.reset()
        currentPreedit = ""
        currentCandidates = []
        updateCandidateBar()
    }

    private func setupView() {
        view.backgroundColor = UIColor.systemGray5

        rootStack.axis = .vertical
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        candidateStack.axis = .horizontal
        candidateStack.alignment = .fill
        candidateStack.distribution = .fillEqually
        candidateStack.spacing = 6
        rootStack.addArrangedSubview(candidateStack)

        keyRowsStack.axis = .vertical
        keyRowsStack.spacing = 6
        rootStack.addArrangedSubview(keyRowsStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 252),
            candidateStack.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    private func rebuildKeyboard() {
        keyRowsStack.arrangedSubviews.forEach { view in
            keyRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let rows = symbolsVisible ? symbolRows() : letterRows()
        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            rowStack.spacing = 6
            for key in row {
                rowStack.addArrangedSubview(makeKeyButton(key))
            }
            keyRowsStack.addArrangedSubview(rowStack)
        }
    }

    private func letterRows() -> [[KeySpec]] {
        [
            "qwertyuiop".map { .character(String($0)) },
            "asdfghjkl".map { .character(String($0)) },
            [.shift] + "zxcvbnm".map { .character(String($0)) } + [.backspace],
            [.globe, .symbols, .space, .modeToggle(englishMode ? "EN" : "ZH"), .enter],
        ]
    }

    private func symbolRows() -> [[KeySpec]] {
        [
            "1234567890".map { .text(String($0)) },
            [".", ",", "?", "!", "'", "-", ":", ";", "/"].map { .text($0) },
            [.text("("), .text(")"), .text("@"), .text("#"), .text("$"), .text("&"), .backspace],
            [.globe, .letters, .space, .modeToggle(englishMode ? "EN" : "ZH"), .enter],
        ]
    }

    private func makeKeyButton(_ key: KeySpec) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(key.title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: key.isWide ? 16 : 18, weight: .medium)
        button.backgroundColor = key.isCommand ? UIColor.systemGray3 : UIColor.systemBackground
        button.layer.cornerRadius = 6
        button.setTitleColor(.label, for: .normal)
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.handle(key)
        }, for: .touchUpInside)
        return button
    }

    private func updateCandidateBar() {
        candidateStack.arrangedSubviews.forEach { view in
            candidateStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if currentPreedit.isEmpty && currentCandidates.isEmpty {
            candidateStack.addArrangedSubview(makeCandidateLabel(""))
            return
        }

        if !currentPreedit.isEmpty {
            candidateStack.addArrangedSubview(makeCandidateLabel(currentPreedit))
        }

        for (index, candidate) in currentCandidates.prefix(5).enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(candidate.text, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            button.backgroundColor = UIColor.systemBackground
            button.layer.cornerRadius = 6
            button.setTitleColor(.label, for: .normal)
            button.addAction(UIAction { [weak self] _ in
                self?.commitCandidate(index)
            }, for: .touchUpInside)
            candidateStack.addArrangedSubview(button)
        }
    }

    private func makeCandidateLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.backgroundColor = UIColor.systemGray6
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        return label
    }

    private func handle(_ key: KeySpec) {
        switch key.kind {
        case .character(let value):
            feedCharacter(value)
        case .text(let value):
            handleTextKey(value)
        case .space:
            applyOrInsert(core?.feed(keyCode: IosKeyCodeValue.space, text: " "), fallback: " ")
        case .enter:
            applyOrInsert(core?.feed(keyCode: IosKeyCodeValue.enter, text: "\n"), fallback: "\n")
        case .backspace:
            handleBackspace()
        case .shift:
            shifted.toggle()
            rebuildKeyboard()
        case .globe:
            advanceToNextInputMode()
        case .symbols:
            symbolsVisible = true
            rebuildKeyboard()
        case .letters:
            symbolsVisible = false
            rebuildKeyboard()
        case .modeToggle:
            englishMode.toggle()
            if let output = core?.toggleMode() {
                apply(output)
            }
            rebuildKeyboard()
        }
    }
}

private extension KeyboardViewController {
    func feedCharacter(_ value: String) {
        let text = shifted ? value.uppercased() : value
        let output = core?.feed(
            keyCode: IosKeyCodeValue.character,
            text: text,
            shift: shifted
        )
        shifted = false
        apply(output)
        rebuildKeyboard()
    }

    func handleTextKey(_ value: String) {
        if let keyCode = coreKeyCode(for: value) {
            applyOrInsert(core?.feed(keyCode: keyCode, text: value), fallback: value)
            return
        }

        endActiveInputIfNeeded()
        textDocumentProxy.insertText(value)
    }

    func handleBackspace() {
        if hasActiveInput {
            apply(core?.feed(keyCode: IosKeyCodeValue.backspace))
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    func commitCandidate(_ index: Int) {
        apply(core?.commitCandidate(index: index))
    }

    func applyOrInsert(_ output: IosPinyinOutput?, fallback: String) {
        let previousActiveInput = hasActiveInput
        apply(output)
        if !previousActiveInput && output?.shouldCommit != true {
            textDocumentProxy.insertText(fallback)
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

        if output.shouldCommit, !output.commitText.isEmpty {
            textDocumentProxy.insertText(output.commitText)
        }

        currentPreedit = output.preedit
        currentCandidates = output.shouldShowCandidates ? output.candidates : []
        updateCandidateBar()
    }

    var hasActiveInput: Bool {
        !currentPreedit.isEmpty || !currentCandidates.isEmpty
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
}

private struct KeySpec {
    enum Kind {
        case character(String)
        case text(String)
        case space
        case enter
        case backspace
        case shift
        case globe
        case symbols
        case letters
        case modeToggle(String)
    }

    let kind: Kind
    let title: String
    let isCommand: Bool
    let isWide: Bool

    static func character(_ value: String) -> Self {
        Self(kind: .character(value), title: value.uppercased(), isCommand: false, isWide: false)
    }

    static func text(_ value: String) -> Self {
        Self(kind: .text(value), title: value, isCommand: false, isWide: false)
    }

    static let shift = Self(kind: .shift, title: "Shift", isCommand: true, isWide: true)
    static let backspace = Self(kind: .backspace, title: "Delete", isCommand: true, isWide: true)
    static let globe = Self(kind: .globe, title: "Globe", isCommand: true, isWide: true)
    static let symbols = Self(kind: .symbols, title: "123", isCommand: true, isWide: true)
    static let letters = Self(kind: .letters, title: "ABC", isCommand: true, isWide: true)
    static let space = Self(kind: .space, title: "Space", isCommand: false, isWide: true)
    static let enter = Self(kind: .enter, title: "Return", isCommand: true, isWide: true)

    static func modeToggle(_ title: String) -> Self {
        Self(kind: .modeToggle(title), title: title, isCommand: true, isWide: true)
    }
}
