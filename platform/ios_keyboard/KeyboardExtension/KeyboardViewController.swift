import UIKit

final class KeyboardViewController: UIInputViewController {
    private var core: IosPinyinCoreBridge?
    private let rootStack = UIStackView()
    private let candidateBar = UIStackView()
    private let candidateScrollView = CandidateScrollView()
    private let candidateStack = UIStackView()
    private let keyRowsStack = UIStackView()
    private let expandedCandidateView = UIView()
    private let expandedCandidateGrid = UIStackView()
    private let expandedCandidatePageLabel = UILabel()
    private let preferencesView = UIView()
    private let preeditLabel = UILabel()
    private let candidateDivider = UIView()
    private let settingsButton = UIButton(type: .system)
    private let expandCandidateButton = UIButton(type: .system)
    private let previousCandidatePageButton = UIButton(type: .system)
    private let nextCandidatePageButton = UIButton(type: .system)
    private let expandedPreviousPageButton = UIButton(type: .system)
    private let expandedNextPageButton = UIButton(type: .system)
    private let layoutSegmentedControl = UISegmentedControl(items: ["全键", "九宫"])
    private let scriptSegmentedControl = UISegmentedControl(items: ["简体", "繁體"])
    private let predictionSwitch = UISwitch()
    private let learningSwitch = UISwitch()
    private let preferencesStatusLabel = UILabel()
    private var candidateButtons: [UIButton] = []
    private var expandedCandidateButtons: [UIButton] = []
    private weak var shiftButton: UIButton?
    private weak var modeButton: UIButton?
    private weak var spaceButton: UIButton?
    private var currentPreedit = ""
    private var currentCandidates: [IosPinyinCandidate] = []
    private var candidatePage = 0
    private var candidatePageReachedEnd = false
    private var candidatesExpanded = false
    private let keyFeedbackGenerator = UISelectionFeedbackGenerator()
    private var renderedCandidateSignature: [String] = []
    private var shifted = false
    private var symbolsVisible = false
    private var extendedSymbolsVisible = false
    private var nineKeyNumbersVisible = false
    private var englishMode = false
    private var preferredLayout = IosSettingsStore.keyboardLayout()
    private var chineseScript = IosSettingsStore.chineseScript()
    private var preferencesVisible = false
    private var pendingSelfTextChangeCallbacks = 0
    private var pendingSelfTextChangeDocumentIdentifier: UUID?
    private var pendingSelfTextChangeContexts: [String?] = []
    private var selfTextChangeCallbackDeadline: TimeInterval = 0
    private let selfTextChangeCallbackWindow: TimeInterval = 0.25
    private var lastNeedsInputModeSwitchKey = true
    private var coreUnavailable = false
    private var localAiSuspendedForMemoryPressure = false
    private let trayGradient = CAGradientLayer()
    private var minimumHeightConstraint: NSLayoutConstraint?
    private var quickPunctuationPopup: NineKeyPunctuationPopupView?
    private var quickPunctuationGestureStart = CGPoint.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = ensureCore()
        keyFeedbackGenerator.prepare()
        setupView()
        rebuildKeyboard()
        updateCandidateBar()
        refreshPreferenceControls()
#if DEBUG
        runKeyboardSmokeIfRequested()
#endif
    }

    override func textWillChange(_ textInput: UITextInput?) {
        if consumePendingSelfTextChangeCallback() {
            return
        }

        if let output = ensureCore()?.reset() {
            englishMode = output.isEnglishMode
        }
        currentPreedit = ""
        currentCandidates = []
        candidatesExpanded = false
        refreshKeyStates()
        updateCandidateBar()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        refreshMinimumHeight()
        if lastNeedsInputModeSwitchKey != needsInputModeSwitchKey {
            lastNeedsInputModeSwitchKey = needsInputModeSwitchKey
            rebuildKeyboard()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        trayGradient.frame = view.bounds
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        localAiSuspendedForMemoryPressure = true
        core?.setSecureInput(true)
    }

    private func setupView() {
        view.accessibilityIdentifier = "private-pinyin-keyboard-root"
        view.backgroundColor = StationKeyboardTheme.trayBottom
        trayGradient.colors = [
            StationKeyboardTheme.trayTop.cgColor,
            StationKeyboardTheme.trayBottom.cgColor,
        ]
        trayGradient.startPoint = CGPoint(x: 0.5, y: 0)
        trayGradient.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(trayGradient, at: 0)

        let topBorder = UIView()
        topBorder.backgroundColor = StationKeyboardTheme.trayBorder
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBorder)

        rootStack.axis = .vertical
        rootStack.spacing = 9
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        setupCandidateBar()

        keyRowsStack.axis = .vertical
        keyRowsStack.distribution = .fillEqually
        keyRowsStack.spacing = 9
        rootStack.addArrangedSubview(keyRowsStack)

        setupExpandedCandidateView()
        expandedCandidateView.isHidden = true
        rootStack.addArrangedSubview(expandedCandidateView)

        setupPreferencesView()
        preferencesView.isHidden = true
        rootStack.addArrangedSubview(preferencesView)

        minimumHeightConstraint = view.heightAnchor.constraint(greaterThanOrEqualToConstant: 278)
        NSLayoutConstraint.activate([
            topBorder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBorder.topAnchor.constraint(equalTo: view.topAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            minimumHeightConstraint!,
            candidateBar.heightAnchor.constraint(equalToConstant: 46),
        ])
    }

    private func setupCandidateBar() {
        candidateBar.axis = .horizontal
        candidateBar.alignment = .center
        candidateBar.spacing = 8
        candidateBar.isLayoutMarginsRelativeArrangement = true
        candidateBar.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)
        rootStack.addArrangedSubview(candidateBar)

        configurePreeditLabel()
        candidateBar.addArrangedSubview(preeditLabel)

        candidateDivider.backgroundColor = StationKeyboardTheme.divider
        candidateDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        candidateDivider.heightAnchor.constraint(equalToConstant: 20).isActive = true
        candidateDivider.isHidden = true
        candidateBar.addArrangedSubview(candidateDivider)

        candidateScrollView.showsHorizontalScrollIndicator = false
        candidateScrollView.showsVerticalScrollIndicator = false
        candidateScrollView.alwaysBounceHorizontal = true
        candidateScrollView.canCancelContentTouches = true
        candidateScrollView.delaysContentTouches = false
        candidateScrollView.isDirectionalLockEnabled = true
        candidateScrollView.decelerationRate = .fast
        candidateScrollView.accessibilityLabel = "候选词"
        candidateScrollView.accessibilityHint = "左右滑动查看更多候选"
        candidateScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        candidateScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureCandidatePageButton(
            previousCandidatePageButton,
            systemImageName: "chevron.left",
            accessibilityLabel: "上一组候选"
        ) { [weak self] in
            self?.turnCandidatePage(-1)
        }
        candidateBar.addArrangedSubview(previousCandidatePageButton)
        candidateBar.addArrangedSubview(candidateScrollView)

        candidateStack.axis = .horizontal
        candidateStack.alignment = .center
        candidateStack.distribution = .fill
        candidateStack.spacing = 16
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScrollView.addSubview(candidateStack)

        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScrollView.frameLayoutGuide.heightAnchor),
        ])

        for index in 0..<IosPinyinCoreBridge.preferredCandidatePageSize {
            let button = makeCandidateButton(index: index)
            button.isHidden = true
            candidateButtons.append(button)
            candidateStack.addArrangedSubview(button)
        }

        configureCandidatePageButton(
            nextCandidatePageButton,
            systemImageName: "chevron.right",
            accessibilityLabel: "下一组候选"
        ) { [weak self] in
            self?.turnCandidatePage(1)
        }
        candidateBar.addArrangedSubview(nextCandidatePageButton)

        configureCandidateToolButton(
            expandCandidateButton,
            systemImageName: "chevron.down",
            accessibilityLabel: "展开全部候选"
        ) { [weak self] in
            self?.toggleExpandedCandidates()
        }
        expandCandidateButton.accessibilityIdentifier = "private-pinyin-expand-candidates"
        expandCandidateButton.isHidden = true
        candidateBar.addArrangedSubview(expandCandidateButton)

        configureCandidateToolButton(
            settingsButton,
            systemImageName: "ellipsis",
            accessibilityLabel: "更多工具与键盘设置"
        ) { [weak self] in
            self?.togglePreferences()
        }
        candidateBar.addArrangedSubview(settingsButton)
    }

    private func setupExpandedCandidateView() {
        expandedCandidateView.accessibilityIdentifier = "private-pinyin-expanded-candidates"
        expandedCandidateView.backgroundColor = .clear

        expandedCandidatePageLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        expandedCandidatePageLabel.textColor = StationKeyboardTheme.secondaryText
        expandedCandidatePageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        configureExpandedPageButton(
            expandedPreviousPageButton,
            systemImageName: "chevron.left",
            accessibilityLabel: "上一组候选"
        ) { [weak self] in
            self?.turnCandidatePage(-1)
        }
        configureExpandedPageButton(
            expandedNextPageButton,
            systemImageName: "chevron.right",
            accessibilityLabel: "下一组候选"
        ) { [weak self] in
            self?.turnCandidatePage(1)
        }

        let header = UIStackView(arrangedSubviews: [
            expandedCandidatePageLabel,
            expandedPreviousPageButton,
            expandedNextPageButton,
        ])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        header.heightAnchor.constraint(equalToConstant: 32).isActive = true

        expandedCandidateGrid.axis = .vertical
        expandedCandidateGrid.alignment = .fill
        expandedCandidateGrid.distribution = .fillEqually
        expandedCandidateGrid.spacing = 8

        for rowIndex in 0..<3 {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.distribution = .fillEqually
            row.spacing = 8
            for columnIndex in 0..<3 {
                let index = rowIndex * 3 + columnIndex
                let button = makeExpandedCandidateButton(index: index)
                expandedCandidateButtons.append(button)
                row.addArrangedSubview(button)
            }
            expandedCandidateGrid.addArrangedSubview(row)
        }

        let content = UIStackView(arrangedSubviews: [header, expandedCandidateGrid])
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        expandedCandidateView.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: expandedCandidateView.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: expandedCandidateView.trailingAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: expandedCandidateView.topAnchor),
            content.bottomAnchor.constraint(equalTo: expandedCandidateView.bottomAnchor),
        ])
    }

    private func configureExpandedPageButton(
        _ button: UIButton,
        systemImageName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        button.setImage(UIImage(systemName: systemImageName), for: .normal)
        button.tintColor = StationKeyboardTheme.secondaryText
        button.backgroundColor = StationKeyboardTheme.functionKey
        button.layer.cornerRadius = 6
        button.layer.cornerCurve = .continuous
        button.accessibilityLabel = accessibilityLabel
        button.addAction(UIAction { [weak self] _ in
            self?.provideSelectionFeedback()
            action()
        }, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 42).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    private func makeExpandedCandidateButton(index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "private-pinyin-expanded-candidate-\(index)"
        button.titleLabel?.font = UIFont.systemFont(ofSize: 23, weight: index == 0 ? .bold : .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.68
        button.titleLabel?.numberOfLines = 1
        button.setTitleColor(
            index == 0 ? StationKeyboardTheme.accent : StationKeyboardTheme.primaryText,
            for: .normal
        )
        button.backgroundColor = StationKeyboardTheme.functionKey
        button.layer.cornerRadius = 7
        button.layer.cornerCurve = .continuous
        button.layer.borderColor = StationKeyboardTheme.trayBorder.cgColor
        button.layer.borderWidth = 1
        button.addAction(UIAction { [weak self] _ in
            self?.commitCandidate(index)
        }, for: .touchUpInside)
        return button
    }

    private func configureCandidateToolButton(
        _ button: UIButton,
        systemImageName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        button.setImage(UIImage(systemName: systemImageName), for: .normal)
        button.tintColor = StationKeyboardTheme.toolText
        button.backgroundColor = .clear
        button.accessibilityLabel = accessibilityLabel
        button.addAction(UIAction { [weak self] _ in
            self?.provideSelectionFeedback()
            action()
        }, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    private func configureCandidatePageButton(
        _ button: UIButton,
        systemImageName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        button.setImage(UIImage(systemName: systemImageName), for: .normal)
        button.tintColor = StationKeyboardTheme.secondaryText
        button.backgroundColor = .clear
        button.accessibilityLabel = accessibilityLabel
        button.addAction(UIAction { [weak self] _ in
            self?.provideSelectionFeedback()
            action()
        }, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        button.isHidden = true
    }

    private func configurePreeditLabel() {
        preeditLabel.textAlignment = .left
        preeditLabel.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        preeditLabel.textColor = StationKeyboardTheme.accent
        preeditLabel.backgroundColor = .clear
        preeditLabel.adjustsFontSizeToFitWidth = true
        preeditLabel.minimumScaleFactor = 0.72
        preeditLabel.setContentHuggingPriority(.required, for: .horizontal)
        preeditLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        preeditLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 92).isActive = true
    }

    private func makeCandidateButton(index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "private-pinyin-candidate-\(index)"
        button.titleLabel?.font = UIFont.systemFont(ofSize: 21, weight: index == 0 ? .bold : .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.72
        button.backgroundColor = .clear
        button.setTitleColor(
            index == 0 ? StationKeyboardTheme.accent : StationKeyboardTheme.candidateText,
            for: .normal
        )
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in
            self?.commitCandidate(index)
        }, for: .touchUpInside)
        return button
    }

    private func setupPreferencesView() {
        preferencesView.backgroundColor = StationKeyboardTheme.functionKey
        preferencesView.layer.cornerRadius = 8
        preferencesView.layer.cornerCurve = .continuous
        preferencesView.layer.borderColor = StationKeyboardTheme.trayBorder.cgColor
        preferencesView.layer.borderWidth = 1

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        preferencesView.addSubview(stack)

        configurePreferenceSegmentedControl(
            layoutSegmentedControl,
            accessibilityLabel: "拼音键盘布局"
        ) { [weak self] in
            self?.setPreferredLayout()
        }
        configurePreferenceSegmentedControl(
            scriptSegmentedControl,
            accessibilityLabel: "中文输出字形"
        ) { [weak self] in
            self?.setChineseScript()
        }

        predictionSwitch.onTintColor = StationKeyboardTheme.accent
        predictionSwitch.accessibilityLabel = "显示预测候选"
        predictionSwitch.addAction(UIAction { [weak self] _ in
            self?.setPredictionEnabled()
        }, for: .valueChanged)

        learningSwitch.onTintColor = StationKeyboardTheme.accent
        learningSwitch.accessibilityLabel = "记住我常选的词"
        learningSwitch.addAction(UIAction { [weak self] _ in
            self?.setLearningEnabled()
        }, for: .valueChanged)

        stack.addArrangedSubview(makeSegmentedPreferenceRow(
            title: "拼音布局",
            detail: "全键与九宫格可随时切换",
            control: layoutSegmentedControl
        ))
        stack.addArrangedSubview(makeDivider())
        stack.addArrangedSubview(makeSegmentedPreferenceRow(
            title: "输出字形",
            detail: "系统通用繁体，非完整台港本地化",
            control: scriptSegmentedControl
        ))
        stack.addArrangedSubview(makeDivider())
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

    private func configurePreferenceSegmentedControl(
        _ control: UISegmentedControl,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        control.selectedSegmentTintColor = StationKeyboardTheme.accent
        control.backgroundColor = StationKeyboardTheme.trayBottom
        control.setTitleTextAttributes([
            .foregroundColor: StationKeyboardTheme.secondaryText,
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
        ], for: .normal)
        control.setTitleTextAttributes([
            .foregroundColor: StationKeyboardTheme.returnText,
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        ], for: .selected)
        control.accessibilityLabel = accessibilityLabel
        control.addAction(UIAction { _ in action() }, for: .valueChanged)
    }

    private func makePreferenceRow(title: String, detail: String, toggle: UISwitch) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = StationKeyboardTheme.primaryText

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = StationKeyboardTheme.weakText

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

    private func makeSegmentedPreferenceRow(
        title: String,
        detail: String,
        control: UISegmentedControl
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = StationKeyboardTheme.primaryText

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = StationKeyboardTheme.weakText

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 2

        let row = UIStackView(arrangedSubviews: [labels, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        control.widthAnchor.constraint(equalToConstant: 130).isActive = true
        return row
    }

    private func makePreferenceFooter() -> UIView {
        preferencesStatusLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        preferencesStatusLabel.textColor = StationKeyboardTheme.weakText
        preferencesStatusLabel.numberOfLines = 2
        preferencesStatusLabel.adjustsFontSizeToFitWidth = true
        preferencesStatusLabel.minimumScaleFactor = 0.75

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("清除", for: .normal)
        clearButton.setImage(UIImage(systemName: "trash"), for: .normal)
        clearButton.tintColor = StationKeyboardTheme.accent
        clearButton.setTitleColor(StationKeyboardTheme.accent, for: .normal)
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
        divider.backgroundColor = StationKeyboardTheme.divider
        divider.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale).isActive = true
        return divider
    }

    private func rebuildKeyboard() {
        dismissQuickPunctuationPopup()
        keyRowsStack.arrangedSubviews.forEach { view in
            keyRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        shiftButton = nil
        modeButton = nil
        spaceButton = nil

        if !symbolsVisible, usesNineKeyLayout {
            keyRowsStack.addArrangedSubview(
                nineKeyNumbersVisible ? makeNineKeyNumberGrid() : makeNineKeyGrid()
            )
            refreshMinimumHeight()
            refreshKeyStates()
            return
        }

        let rows = symbolsVisible ? symbolRows() : letterRows()
        refreshMinimumHeight()
        for (rowIndex, row) in rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fill
            rowStack.spacing = usesNineKeyLayout ? 7 : 6

            let rowHeight = usesNineKeyLayout ? 52.0 : 44.0
            let rowHeightConstraint = rowStack.heightAnchor.constraint(equalToConstant: rowHeight)
            rowHeightConstraint.priority = .defaultHigh
            rowHeightConstraint.isActive = true

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
        guard !usesNineKeyLayout, index == 1, !extendedSymbolsVisible else {
            return 0
        }
        return symbolsVisible ? 14 : 10
    }

    private func letterRows() -> [[KeySpec]] {
        [
            "qwertyuiop".map { .character(String($0)) },
            "asdfghjkl".map { .character(String($0)) },
            [.shift] + "zxcvbnm".map { .character(String($0)) } + [.backspace],
            qwertyCommandRow(),
        ]
    }

    private func makeNineKeyGrid() -> UIView {
        let topRow = makeAdaptiveKeyRow([
            .nineKeyNumbers,
            .nineKeyPunctuation,
            .nineKeyDigit(2, letters: "ABC"),
            .nineKeyDigit(3, letters: "DEF"),
            .backspace,
        ])
        let middleRow = makeAdaptiveKeyRow([
            .nineKeyMoreSymbols,
            .nineKeyDigit(4, letters: "GHI"),
            .nineKeyDigit(5, letters: "JKL"),
            .nineKeyDigit(6, letters: "MNO"),
            .modeToggle,
        ])

        let leadingButton = makeKeyButton(needsInputModeSwitchKey ? .globe : .qwertyLayout)
        let enterButton = makeKeyButton(.enter)
        let lowerCenterTop = makeAdaptiveKeyRow([
            .nineKeyDigit(7, letters: "PQRS"),
            .nineKeyDigit(8, letters: "TUV"),
            .nineKeyDigit(9, letters: "WXYZ"),
        ])
        let candidateButton = makeKeyButton(.candidateNextPage)
        let spaceButton = makeKeyButton(.space)
        let lowerCenterBottom = UIStackView(arrangedSubviews: [candidateButton, spaceButton])
        lowerCenterBottom.axis = .horizontal
        lowerCenterBottom.alignment = .fill
        lowerCenterBottom.distribution = .fill
        lowerCenterBottom.spacing = 7

        let lowerCenter = UIStackView(arrangedSubviews: [lowerCenterTop.stack, lowerCenterBottom])
        lowerCenter.axis = .vertical
        lowerCenter.alignment = .fill
        lowerCenter.distribution = .fill
        lowerCenter.spacing = 9

        let lowerRow = UIStackView(arrangedSubviews: [leadingButton, lowerCenter, enterButton])
        lowerRow.axis = .horizontal
        lowerRow.alignment = .fill
        lowerRow.distribution = .fill
        lowerRow.spacing = 7

        let grid = UIStackView(arrangedSubviews: [topRow.stack, middleRow.stack, lowerRow])
        grid.axis = .vertical
        grid.alignment = .fill
        grid.distribution = .fill
        grid.spacing = 9

        // Cross-row constraints are only legal after every row belongs to the
        // same grid hierarchy. Activating them earlier crashes the extension.
        var gridConstraints = [
            candidateButton.widthAnchor.constraint(
                equalTo: lowerCenterTop.buttons[0].widthAnchor
            ),
            leadingButton.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor),
            enterButton.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor),
            middleRow.stack.heightAnchor.constraint(equalTo: topRow.stack.heightAnchor),
            lowerCenterTop.stack.heightAnchor.constraint(equalTo: topRow.stack.heightAnchor),
            lowerCenterBottom.heightAnchor.constraint(equalTo: topRow.stack.heightAnchor),
            lowerRow.heightAnchor.constraint(
                equalTo: topRow.stack.heightAnchor,
                multiplier: 2,
                constant: 9
            ),
        ]
        gridConstraints.append(contentsOf: middleRow.buttons.map {
            $0.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor)
        })
        gridConstraints.append(contentsOf: lowerCenterTop.buttons.map {
            $0.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor)
        })
        NSLayoutConstraint.activate(gridConstraints)
        return grid
    }

    private func makeNineKeyNumberGrid() -> UIView {
        let topRow = makeAdaptiveKeyRow([
            .nineKeyLetters,
            .text("1"),
            .text("2"),
            .text("3"),
            .backspace,
        ])
        let middleRow = makeAdaptiveKeyRow([
            .nineKeyMoreSymbols,
            .text("4"),
            .text("5"),
            .text("6"),
            .nineKeyExtendedSymbols,
        ])

        let leadingButton = makeKeyButton(.qwertyLayout)
        let enterButton = makeKeyButton(.enter)
        let lowerCenterTop = makeAdaptiveKeyRow([
            .text("7"),
            .text("8"),
            .text("9"),
        ])
        let lowerCenterBottom = makeAdaptiveKeyRow([
            .nineKeyPunctuation,
            .text("0"),
            .nineKeySpace,
        ])
        let lowerCenter = UIStackView(arrangedSubviews: [
            lowerCenterTop.stack,
            lowerCenterBottom.stack,
        ])
        lowerCenter.axis = .vertical
        lowerCenter.alignment = .fill
        lowerCenter.distribution = .fill
        lowerCenter.spacing = 9

        let lowerRow = UIStackView(arrangedSubviews: [leadingButton, lowerCenter, enterButton])
        lowerRow.axis = .horizontal
        lowerRow.alignment = .fill
        lowerRow.distribution = .fill
        lowerRow.spacing = 7

        let grid = UIStackView(arrangedSubviews: [topRow.stack, middleRow.stack, lowerRow])
        grid.axis = .vertical
        grid.alignment = .fill
        grid.distribution = .fill
        grid.spacing = 9

        var gridConstraints = [
            leadingButton.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor),
            enterButton.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor),
            middleRow.stack.heightAnchor.constraint(equalTo: topRow.stack.heightAnchor),
            lowerCenterTop.stack.heightAnchor.constraint(equalTo: topRow.stack.heightAnchor),
            lowerCenterBottom.stack.heightAnchor.constraint(equalTo: topRow.stack.heightAnchor),
            lowerRow.heightAnchor.constraint(
                equalTo: topRow.stack.heightAnchor,
                multiplier: 2,
                constant: 9
            ),
        ]
        gridConstraints.append(contentsOf: middleRow.buttons.map {
            $0.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor)
        })
        gridConstraints.append(contentsOf: lowerCenterTop.buttons.map {
            $0.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor)
        })
        gridConstraints.append(contentsOf: lowerCenterBottom.buttons.map {
            $0.widthAnchor.constraint(equalTo: topRow.buttons[0].widthAnchor)
        })
        NSLayoutConstraint.activate(gridConstraints)
        return grid
    }

    private func makeAdaptiveKeyRow(_ keys: [KeySpec]) -> (stack: UIStackView, buttons: [UIButton]) {
        let buttons = keys.map(makeKeyButton)
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fillEqually
        row.spacing = 7
        return (row, buttons)
    }

    private func symbolRows() -> [[KeySpec]] {
        if extendedSymbolsVisible {
            return [
                ["【", "】", "{", "}", "#", "%", "^", "*", "+", "="].map { .text($0) },
                ["_", "—", "\\", "|", "~", "《", "》", "$", "&", "·"].map { .text($0) },
                [.symbols.weighted(1.25), .text("…", title: "..."), .text("，"),
                 .text("^^"), .text("?"), .text("!"), .text("'"),
                 .backspace.weighted(1.25)],
                qwertyCommandRow(),
            ]
        }

        return [
            "1234567890".map { .text(String($0)) },
            [".", ",", "?", "!", "'", "-", ":", ";", "/"].map { .text($0) },
            [.extendedSymbols.weighted(1.25), .text("("), .text(")"), .text("@"),
             .text("#"), .text("$"), .text("&"), .backspace.weighted(1.25)],
            qwertyCommandRow(),
        ]
    }

    private func qwertyCommandRow() -> [KeySpec] {
        let leadingKey: KeySpec
        if symbolsVisible, preferredLayout == .nineKey, !englishMode {
            leadingKey = .nineKeyLayout
        } else {
            leadingKey = symbolsVisible ? .letters : .symbols
        }
        var row = [
            leadingKey.weighted(1.6),
        ]
        if needsInputModeSwitchKey {
            row.append(.globe.weighted(1.2))
        }
        row.append(contentsOf: [
            .space.weighted(4.6),
            .modeToggle.weighted(1.4),
            .enter.weighted(1.8),
        ])
        return row
    }

    private func makeKeyButton(_ key: KeySpec) -> UIButton {
        let button = StationKeyButton(style: key.visualStyle)
        let title: String?
        switch key.kind {
        case .space:
            title = englishMode ? "space" : "猫栈拼音"
        case .nineKeySpace:
            title = key.title
        case .modeToggle:
            title = englishMode ? "英" : "中"
        case .enter:
            title = "回车"
        default:
            title = key.title
        }
        button.setTitle(title, for: .normal)
        if let systemImageName = key.systemImageName {
            let image = UIImage(systemName: systemImageName)?.withRenderingMode(.alwaysTemplate)
            button.setCenteredImage(image)
        }
        button.accessibilityLabel = key.accessibilityLabel
        switch key.kind {
        case .character(let value):
            button.accessibilityIdentifier = "private-pinyin-key-\(value.lowercased())"
        case .nineKeyDigit(let value):
            button.accessibilityIdentifier = "private-pinyin-nine-key-\(value)"
        case .globe:
            button.accessibilityIdentifier = "private-pinyin-globe-key"
        case .space, .nineKeySpace:
            button.accessibilityIdentifier = "private-pinyin-space-key"
        case .enter:
            button.accessibilityIdentifier = "private-pinyin-enter-key"
        default:
            break
        }
        button.titleLabel?.font = key.titleFont
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.cornerRadius = usesNineKeyLayout ? 7 : 6
        if case .character(let value) = key.kind {
            // The middle QWERTY row leaves a 10-point outer margin for these
            // edge expansions, so neither hit region overlaps S or K.
            if value == "a" {
                button.hitTestOutsets.left = 10
            } else if value == "l" {
                button.hitTestOutsets.right = 10
            }
        }
        button.isEnabled = key.kind.isInteractive
        button.alpha = key.kind.isInteractive ? 1 : 0
        button.addAction(UIAction { [weak self] _ in
            self?.handle(key)
        }, for: key.activationEvent)
        if case .nineKeyPunctuation = key.kind {
            let gesture = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleQuickPunctuationGesture(_:))
            )
            gesture.minimumPressDuration = 0.18
            gesture.cancelsTouchesInView = true
            button.addGestureRecognizer(gesture)
            button.accessibilityHint = "轻点输入逗号，长按并滑动选择标点"
        }
        if case .enter = key.kind {
            button.accessibilityHint = "提交当前输入，或执行当前输入框的回车操作"
        }

        switch key.kind {
        case .shift:
            shiftButton = button
        case .modeToggle:
            modeButton = button
        case .space:
            spaceButton = button
        default:
            break
        }
        return button
    }

    private func refreshKeyStates() {
        (shiftButton as? StationKeyButton)?.isLatched = shifted
        modeButton?.setTitle(englishMode ? "英" : "中", for: .normal)
        spaceButton?.setTitle(englishMode ? "space" : "猫栈拼音", for: .normal)
    }

    private func updateCandidateBar() {
        if preferencesVisible {
            candidatesExpanded = false
            keyRowsStack.isHidden = true
            expandedCandidateView.isHidden = true
            preeditLabel.text = "键盘偏好设置"
            preeditLabel.isHidden = false
            candidateButtons.forEach { button in
                button.setTitle(nil, for: .normal)
                button.isHidden = true
            }
            settingsButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            settingsButton.isEnabled = true
            candidateScrollView.isHidden = true
            candidateDivider.isHidden = true
            previousCandidatePageButton.isHidden = true
            nextCandidatePageButton.isHidden = true
            expandCandidateButton.isHidden = true
            return
        }

        settingsButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        settingsButton.isEnabled = currentPreedit.isEmpty
        settingsButton.alpha = settingsButton.isEnabled ? 1.0 : 0.45

        let hasCandidates = !currentCandidates.isEmpty
        if !hasCandidates {
            candidatesExpanded = false
        }
        keyRowsStack.isHidden = candidatesExpanded
        expandedCandidateView.isHidden = !candidatesExpanded
        candidateScrollView.isHidden = candidatesExpanded
        let candidateSignature = currentCandidates.map { "\($0.text)\u{1f}\($0.pinyin)" }
        let candidatesChanged = candidateSignature != renderedCandidateSignature
        renderedCandidateSignature = candidateSignature
        previousCandidatePageButton.isHidden = candidatesExpanded || !hasCandidates || candidatePage == 0
        nextCandidatePageButton.isHidden = candidatesExpanded || !hasCandidates
            || currentCandidates.count < sessionCandidatePageSize
            || candidatePageReachedEnd
        expandCandidateButton.isHidden = !hasCandidates
        expandCandidateButton.setImage(
            UIImage(systemName: candidatesExpanded ? "chevron.up" : "chevron.down"),
            for: .normal
        )
        expandCandidateButton.accessibilityLabel = candidatesExpanded
            ? "收起全部候选"
            : "展开全部候选"

        let visiblePreedit = displayedPreedit
        let showPreedit = !visiblePreedit.isEmpty || !hasCandidates
        preeditLabel.text = currentPreedit.isEmpty && coreUnavailable
            ? "输入引擎暂时不可用，请再试一次"
            : visiblePreedit
        preeditLabel.isHidden = !showPreedit
        candidateDivider.isHidden = preeditLabel.isHidden || currentPreedit.isEmpty

        for (index, button) in candidateButtons.enumerated() {
            guard index < currentCandidates.count else {
                button.setTitle(nil, for: .normal)
                button.isHidden = true
                continue
            }
            let candidateText = displayText(currentCandidates[index].text)
            button.setTitle(candidateText, for: .normal)
            button.accessibilityLabel = "候选词 \(candidateText)"
            button.isHidden = false
        }
        if candidatesChanged {
            candidateScrollView.setContentOffset(.zero, animated: false)
        }
        updateExpandedCandidates()
    }

    private func updateExpandedCandidates() {
        expandedCandidatePageLabel.text = "全部候选 · 第 \(candidatePage + 1) 组"
        expandedPreviousPageButton.isEnabled = candidatePage > 0
        expandedPreviousPageButton.alpha = expandedPreviousPageButton.isEnabled ? 1.0 : 0.35
        let hasNextPage = currentCandidates.count >= sessionCandidatePageSize
            && !candidatePageReachedEnd
        expandedNextPageButton.isEnabled = hasNextPage
        expandedNextPageButton.alpha = hasNextPage ? 1.0 : 0.35

        for (index, button) in expandedCandidateButtons.enumerated() {
            guard index < currentCandidates.count else {
                button.setTitle(nil, for: .normal)
                button.accessibilityLabel = nil
                button.isEnabled = false
                button.alpha = 0
                continue
            }
            let candidate = currentCandidates[index]
            let candidateText = displayText(candidate.text)
            button.setTitle(candidateText, for: .normal)
            button.accessibilityLabel = "候选词 \(candidateText)，拼音 \(candidate.pinyin)"
            button.isEnabled = true
            button.alpha = 1
        }
    }

    private func toggleExpandedCandidates() {
        guard !currentCandidates.isEmpty else {
            return
        }
        candidatesExpanded.toggle()
        refreshMinimumHeight()
        updateCandidateBar()
    }

    private func handle(_ key: KeySpec) {
        provideSelectionFeedback()
        switch key.kind {
        case .character(let value):
            feedCharacter(value)
        case .text(let value):
            handleTextKey(value)
        case .nineKeyDigit(let value):
            feedNineKeyDigit(value)
        case .nineKeyPunctuation:
            insertQuickPunctuation("，")
        case .space:
            applyOrInsert(ensureCore()?.feed(keyCode: IosKeyCodeValue.space, text: " "), fallback: " ")
        case .nineKeySpace:
            applyOrInsert(ensureCore()?.feed(keyCode: IosKeyCodeValue.space, text: " "), fallback: " ")
        case .enter:
            applyOrInsert(ensureCore()?.feed(keyCode: IosKeyCodeValue.enter, text: "\n"), fallback: "\n")
        case .backspace:
            handleBackspace()
        case .shift:
            shifted.toggle()
            refreshKeyStates()
        case .globe:
            advanceToNextInputMode()
        case .symbols:
            symbolsVisible = true
            extendedSymbolsVisible = false
            nineKeyNumbersVisible = false
            rebuildKeyboard()
        case .extendedSymbols:
            symbolsVisible = true
            extendedSymbolsVisible = true
            nineKeyNumbersVisible = false
            rebuildKeyboard()
        case .letters:
            symbolsVisible = false
            extendedSymbolsVisible = false
            nineKeyNumbersVisible = false
            rebuildKeyboard()
        case .nineKeyNumbers:
            nineKeyNumbersVisible = true
            rebuildKeyboard()
        case .nineKeyLetters:
            nineKeyNumbersVisible = false
            rebuildKeyboard()
        case .nineKeyLayout:
            symbolsVisible = false
            extendedSymbolsVisible = false
            nineKeyNumbersVisible = false
            selectKeyboardLayout(.nineKey)
        case .qwertyLayout:
            symbolsVisible = false
            extendedSymbolsVisible = false
            nineKeyNumbersVisible = false
            selectKeyboardLayout(.qwerty)
        case .candidateNextPage:
            turnCandidatePage(1)
        case .modeToggle:
            apply(ensureCore()?.toggleMode())
        case .spacer:
            break
        }
    }

    @objc private func handleQuickPunctuationGesture(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else {
            return
        }

        switch gesture.state {
        case .began:
            provideSelectionFeedback()
            quickPunctuationGestureStart = gesture.location(in: view)
            showQuickPunctuationPopup(anchoredTo: button)
        case .changed:
            let location = gesture.location(in: view)
            let upwardDistance = max(0, quickPunctuationGestureStart.y - location.y)
            quickPunctuationPopup?.select(upwardDistance: upwardDistance)
        case .ended:
            let punctuation = quickPunctuationPopup?.selectedPunctuation ?? "，"
            dismissQuickPunctuationPopup()
            insertQuickPunctuation(punctuation)
        case .cancelled, .failed:
            dismissQuickPunctuationPopup()
        default:
            break
        }
    }

    private func showQuickPunctuationPopup(anchoredTo button: UIButton) {
        dismissQuickPunctuationPopup()
        let popup = NineKeyPunctuationPopupView()
        let size = popup.intrinsicContentSize
        let sourceFrame = button.convert(button.bounds, to: view)
        let x = min(
            max(4, sourceFrame.midX - size.width / 2),
            max(4, view.bounds.width - size.width - 4)
        )
        let y = max(4, sourceFrame.maxY - size.height)
        popup.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        view.addSubview(popup)
        quickPunctuationPopup = popup
    }

    private func dismissQuickPunctuationPopup() {
        quickPunctuationPopup?.removeFromSuperview()
        quickPunctuationPopup = nil
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
        let output = ensureCore()?.feed(
            keyCode: IosKeyCodeValue.character,
            text: text,
            shift: wasShifted
        )
        apply(output)
    }

    func handleTextKey(_ value: String) {
        if let keyCode = coreKeyCode(for: value) {
            applyOrInsert(ensureCore()?.feed(keyCode: keyCode, text: value), fallback: value)
            return
        }

        endActiveInputIfNeeded()
        insertDocumentText(value)
    }

    func insertQuickPunctuation(_ punctuation: String) {
        switch punctuation {
        case "，":
            handleTextKey(",")
        case "。":
            handleTextKey(".")
        case "；":
            handleTextKey(";")
        default:
            if hasActiveInput {
                if currentCandidates.isEmpty {
                    apply(ensureCore()?.feed(keyCode: IosKeyCodeValue.enter))
                } else {
                    apply(ensureCore()?.commitCandidate(index: 0))
                }
            }
            insertDocumentText(punctuation)
            currentCandidates = []
            candidatesExpanded = false
            updateCandidateBar()
        }
    }

    func handleBackspace() {
        if hasActiveInput {
            apply(ensureCore()?.feed(keyCode: IosKeyCodeValue.backspace))
        } else {
            deleteDocumentBackward()
        }
    }

    func commitCandidate(_ index: Int) {
        provideSelectionFeedback()
        apply(ensureCore()?.commitCandidate(index: index))
    }

    func provideSelectionFeedback() {
        keyFeedbackGenerator.selectionChanged()
        keyFeedbackGenerator.prepare()
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
            apply(ensureCore()?.feed(keyCode: IosKeyCodeValue.enter, text: "\n"))
        }
    }

    func feedNineKeyDigit(_ value: String) {
        guard value.count == 1, let digit = value.first, ("2"..."9").contains(String(digit)) else {
            return
        }
        apply(ensureCore()?.feed(keyCode: IosKeyCodeValue.nineKeyDigit, text: value))
    }

    func turnCandidatePage(_ delta: Int) {
        guard delta != 0, !currentCandidates.isEmpty else {
            return
        }
        let previousSignature = currentCandidates.map { "\($0.text)\u{1f}\($0.pinyin)" }
        let keyCode = delta < 0 ? IosKeyCodeValue.pageUp : IosKeyCodeValue.pageDown
        guard let output = ensureCore()?.feed(keyCode: keyCode) else {
            updateCandidateBar()
            return
        }
        let nextSignature = output.candidates.map { "\($0.text)\u{1f}\($0.pinyin)" }
        if nextSignature != previousSignature {
            candidatePage = max(0, candidatePage + delta)
            candidatePageReachedEnd = output.candidates.count < sessionCandidatePageSize
        } else if delta > 0 {
            candidatePageReachedEnd = true
        }
        apply(output)
    }

    func ensureCore() -> IosPinyinCoreBridge? {
        if core == nil {
            core = IosPinyinCoreBridge()
        }
        coreUnavailable = core == nil
        core?.setSecureInput(
            localAiSuspendedForMemoryPressure || shouldDisableAiForCurrentInputContext
        )
        return core
    }

    var shouldDisableAiForCurrentInputContext: Bool {
        // iOS replaces third-party keyboards in secure text fields. Numeric and
        // phone traits remain visible, so optional AI fails closed for them too.
        switch textDocumentProxy.keyboardType {
        case .phonePad, .namePhonePad, .numberPad, .decimalPad, .asciiCapableNumberPad:
            return true
        default:
            return false
        }
    }

    func apply(_ output: IosPinyinOutput?) {
        guard let output else {
            updateCandidateBar()
            return
        }

        let modeChanged = englishMode != output.isEnglishMode
        englishMode = output.isEnglishMode

        if output.shouldCommit {
            candidatesExpanded = false
        }

        if output.shouldCommit, !output.commitText.isEmpty {
            insertDocumentText(displayText(output.commitText))
        }

        if output.shouldUpdatePreedit || output.shouldCommit {
            candidatePage = 0
            candidatePageReachedEnd = false
        }

        currentPreedit = output.preedit
        currentCandidates = output.shouldShowCandidates ? output.candidates : []
        if currentCandidates.isEmpty {
            candidatePage = 0
            candidatePageReachedEnd = false
            candidatesExpanded = false
        }
        if modeChanged {
            symbolsVisible = false
            extendedSymbolsVisible = false
            nineKeyNumbersVisible = false
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
        let now = ProcessInfo.processInfo.systemUptime
        let documentIdentifier = textDocumentProxy.documentIdentifier
        if pendingSelfTextChangeDocumentIdentifier != documentIdentifier
            || now > selfTextChangeCallbackDeadline {
            resetPendingSelfTextChangeCallbacks()
        }

        pendingSelfTextChangeDocumentIdentifier = documentIdentifier
        pendingSelfTextChangeCallbacks += 1
        appendPendingSelfTextChangeContext(textDocumentProxy.documentContextBeforeInput)
        selfTextChangeCallbackDeadline = now + selfTextChangeCallbackWindow
        operation()

        if pendingSelfTextChangeCallbacks > 0,
           pendingSelfTextChangeDocumentIdentifier == documentIdentifier {
            appendPendingSelfTextChangeContext(textDocumentProxy.documentContextBeforeInput)
        }
    }

    func consumePendingSelfTextChangeCallback() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard pendingSelfTextChangeCallbacks > 0, now <= selfTextChangeCallbackDeadline else {
            resetPendingSelfTextChangeCallbacks()
            return false
        }

        let documentIdentifier = textDocumentProxy.documentIdentifier
        let context = textDocumentProxy.documentContextBeforeInput
        guard pendingSelfTextChangeDocumentIdentifier == documentIdentifier,
              pendingSelfTextChangeContexts.contains(where: { $0 == context }) else {
            resetPendingSelfTextChangeCallbacks()
            return false
        }

        pendingSelfTextChangeCallbacks -= 1
        if pendingSelfTextChangeCallbacks == 0 {
            resetPendingSelfTextChangeCallbacks()
        }
        return true
    }

    func appendPendingSelfTextChangeContext(_ context: String?) {
        guard !pendingSelfTextChangeContexts.contains(where: { $0 == context }) else {
            return
        }
        pendingSelfTextChangeContexts.append(context)
        if pendingSelfTextChangeContexts.count > 16 {
            pendingSelfTextChangeContexts.removeFirst(
                pendingSelfTextChangeContexts.count - 16
            )
        }
    }

    func resetPendingSelfTextChangeCallbacks() {
        pendingSelfTextChangeCallbacks = 0
        pendingSelfTextChangeDocumentIdentifier = nil
        pendingSelfTextChangeContexts.removeAll(keepingCapacity: true)
        selfTextChangeCallbackDeadline = 0
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

    var sessionCandidatePageSize: Int {
        core?.candidatePageSize ?? IosPinyinCoreBridge.preferredCandidatePageSize
    }

    var displayedPreedit: String {
        guard usesNineKeyLayout, !currentPreedit.isEmpty else {
            return currentPreedit
        }
        guard let pinyin = currentCandidates.first?.pinyin
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !pinyin.isEmpty
        else {
            return currentPreedit
        }
        return pinyin
    }

    func displayText(_ text: String) -> String {
        IosChineseTextConverter.convert(text, to: chineseScript)
    }

    func refreshMinimumHeight() {
        if preferencesVisible {
            minimumHeightConstraint?.constant = 368
        } else if traitCollection.verticalSizeClass == .compact {
            minimumHeightConstraint?.constant = 216
        } else {
            minimumHeightConstraint?.constant = candidatesExpanded || usesNineKeyLayout ? 310 : 278
        }
    }

    func selectKeyboardLayout(_ layout: IosKeyboardLayout) {
        guard preferredLayout != layout else {
            rebuildKeyboard()
            return
        }

        if hasActiveInput {
            apply(ensureCore()?.reset())
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
        candidatesExpanded = false
        keyRowsStack.isHidden = preferencesVisible
        expandedCandidateView.isHidden = true
        preferencesView.isHidden = !preferencesVisible
        refreshMinimumHeight()
        if preferencesVisible {
            currentCandidates = []
            candidatePage = 0
            refreshPreferenceControls()
        }
        updateCandidateBar()
    }

    func refreshPreferenceControls() {
        layoutSegmentedControl.selectedSegmentIndex = preferredLayout == .nineKey ? 1 : 0
        chineseScript = IosSettingsStore.chineseScript()
        scriptSegmentedControl.selectedSegmentIndex = chineseScript == .traditional ? 1 : 0
        predictionSwitch.isOn = IosSettingsStore.isPredictionEnabled()
        learningSwitch.isOn = IosSettingsStore.isLearningEnabled()
        learningSwitch.isEnabled = IosSettingsStore.canEnableLearning
        preferencesStatusLabel.text = IosSettingsStore.keyboardStorageDescription(
            hasFullAccess: hasFullAccess
        )
    }

    func setPreferredLayout() {
        let layout: IosKeyboardLayout = layoutSegmentedControl.selectedSegmentIndex == 1
            ? .nineKey
            : .qwerty
        selectKeyboardLayout(layout)
        preferencesStatusLabel.text = layout == .nineKey ? "已切换为九宫格拼音" : "已切换为全键拼音"
    }

    func setChineseScript() {
        let script: IosChineseScript = scriptSegmentedControl.selectedSegmentIndex == 1
            ? .traditional
            : .simplified
        guard IosSettingsStore.setChineseScript(script) else {
            scriptSegmentedControl.selectedSegmentIndex = chineseScript == .traditional ? 1 : 0
            preferencesStatusLabel.text = "无法保存中文输出字形"
            return
        }
        chineseScript = script
        updateCandidateBar()
        preferencesStatusLabel.text = script == .traditional ? "已切换为繁体中文" : "已切换为简体中文"
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
            _ = ensureCore()
            clearCompositionState()
            preferencesStatusLabel.text = removed == 0 ? "没有本机学习记录" : "本机学习记录已清除"
        } catch {
            _ = ensureCore()
            preferencesStatusLabel.text = "无法清除本机学习记录"
        }
    }

    func reloadCoreAfterSettingsChange(status: String) {
        core = nil
        _ = ensureCore()
        clearCompositionState()
        preferencesStatusLabel.text = core == nil ? "输入引擎重新载入失败" : status
    }

    func clearCompositionState() {
        currentPreedit = ""
        currentCandidates = []
        candidatePage = 0
        candidatesExpanded = false
        updateCandidateBar()
    }

#if DEBUG
    func runKeyboardSmokeIfRequested() {
        let defaults = UserDefaults.standard
        let expandedCandidatesKey = "private_pinyin.debug.expanded_candidates_smoke"
        if defaults.bool(forKey: expandedCandidatesKey) {
            defaults.set(false, forKey: expandedCandidatesKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else {
                    return
                }
                self.feedCharacter("w")
                self.feedCharacter("a")
                self.candidatesExpanded = !self.currentCandidates.isEmpty
                self.updateCandidateBar()
                NSLog(
                    "PRIVATE_PINYIN_EXPANDED_CANDIDATES_SMOKE visible=%@ count=%ld",
                    self.candidatesExpanded ? "true" : "false",
                    self.currentCandidates.count
                )
            }
        }

        let key = "private_pinyin.debug.keyboard_smoke"
        guard defaults.bool(forKey: key) else {
            return
        }
        defaults.set(false, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else {
                return
            }
            for digit in ["6", "4", "4", "2", "6"] {
                self.feedNineKeyDigit(digit)
            }

            guard let candidateIndex = self.currentCandidates.firstIndex(where: { $0.text == "你好" }) else {
                NSLog("PRIVATE_PINYIN_KEYBOARD_SMOKE candidate_found=false")
                return
            }

            self.commitCandidate(candidateIndex)
            let committed = self.textDocumentProxy.documentContextBeforeInput?.hasSuffix("你好") == true
            NSLog("PRIVATE_PINYIN_KEYBOARD_SMOKE candidate_found=true committed=\(committed)")
        }
    }
#endif
}

private struct KeySpec {
    enum Kind {
        case character(String)
        case text(String)
        case nineKeyDigit(String)
        case nineKeyPunctuation
        case space
        case nineKeySpace
        case enter
        case backspace
        case shift
        case globe
        case symbols
        case extendedSymbols
        case letters
        case nineKeyNumbers
        case nineKeyLetters
        case nineKeyLayout
        case qwertyLayout
        case candidateNextPage
        case modeToggle
        case spacer
    }

    let kind: Kind
    let title: String?
    let systemImageName: String?
    let accessibilityLabel: String
    let isCommand: Bool
    let isWide: Bool
    let widthWeight: CGFloat

    var activationEvent: UIControl.Event {
        switch kind {
        case .character, .text, .nineKeyDigit, .space, .nineKeySpace, .enter, .backspace:
            return .touchDown
        case .nineKeyPunctuation, .shift, .globe, .symbols, .letters, .nineKeyNumbers,
             .nineKeyLetters, .nineKeyLayout, .extendedSymbols, .qwertyLayout,
             .candidateNextPage, .modeToggle, .spacer:
            return .touchUpInside
        }
    }

    var visualStyle: StationKeyVisualStyle {
        switch kind {
        case .character, .text, .nineKeyDigit:
            return .letter
        case .space, .nineKeySpace:
            return .space
        case .modeToggle:
            return .mode
        case .enter:
            return .returnKey
        case .nineKeyPunctuation, .backspace, .shift, .globe,
             .symbols, .extendedSymbols, .letters, .nineKeyLayout,
             .nineKeyNumbers, .nineKeyLetters, .qwertyLayout, .candidateNextPage, .spacer:
            return .function
        }
    }

    var titleFont: UIFont {
        switch kind {
        case .character:
            return UIFont.systemFont(ofSize: 20, weight: .semibold)
        case .nineKeyDigit:
            return UIFont.systemFont(ofSize: 22, weight: .semibold)
        case .text, .nineKeyPunctuation:
            return UIFont.systemFont(ofSize: 18, weight: .medium)
        case .space, .nineKeySpace, .modeToggle, .enter, .symbols, .extendedSymbols,
             .letters, .nineKeyNumbers, .nineKeyLetters, .nineKeyLayout,
             .qwertyLayout, .candidateNextPage:
            return UIFont.systemFont(ofSize: 15, weight: .semibold)
        case .backspace, .shift, .globe, .spacer:
            return UIFont.systemFont(ofSize: 16, weight: .medium)
        }
    }

    func weighted(_ weight: CGFloat) -> Self {
        Self(
            kind: kind,
            title: title,
            systemImageName: systemImageName,
            accessibilityLabel: accessibilityLabel,
            isCommand: isCommand,
            isWide: isWide,
            widthWeight: weight
        )
    }

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
        text(value, title: value)
    }

    static func text(_ value: String, title: String) -> Self {
        Self(
            kind: .text(value),
            title: title,
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
            title: letters,
            systemImageName: nil,
            accessibilityLabel: "九宫格 \(value) \(letters)",
            isCommand: false,
            isWide: false,
            widthWeight: 1
        )
    }

    static let nineKeyPunctuation = Self(
        kind: .nineKeyPunctuation,
        title: "，。？！",
        systemImageName: nil,
        accessibilityLabel: "快捷中文标点",
        isCommand: true,
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
        widthWeight: 1.5
    )
    static let backspace = Self(
        kind: .backspace,
        title: nil,
        systemImageName: "delete.left",
        accessibilityLabel: "删除",
        isCommand: true,
        isWide: true,
        widthWeight: 1.5
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
    static let nineKeyNumbers = Self(
        kind: .nineKeyNumbers,
        title: "123",
        systemImageName: nil,
        accessibilityLabel: "九宫格数字键盘",
        isCommand: true,
        isWide: true,
        widthWeight: 1
    )
    static let nineKeyLetters = Self(
        kind: .nineKeyLetters,
        title: "拼音",
        systemImageName: nil,
        accessibilityLabel: "返回九宫格拼音",
        isCommand: true,
        isWide: true,
        widthWeight: 1
    )
    static let extendedSymbols = Self(
        kind: .extendedSymbols,
        title: "#+=",
        systemImageName: nil,
        accessibilityLabel: "更多符号",
        isCommand: true,
        isWide: true,
        widthWeight: 1.2
    )
    static let nineKeyMoreSymbols = Self(
        kind: .extendedSymbols,
        title: "#@\u{00a5}",
        systemImageName: nil,
        accessibilityLabel: "更多符号",
        isCommand: true,
        isWide: true,
        widthWeight: 1
    )
    static let nineKeyExtendedSymbols = Self(
        kind: .extendedSymbols,
        title: "更多",
        systemImageName: nil,
        accessibilityLabel: "更多符号",
        isCommand: true,
        isWide: true,
        widthWeight: 1
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
    static let qwertyLayout = Self(
        kind: .qwertyLayout,
        title: "ABC",
        systemImageName: nil,
        accessibilityLabel: "切换到全键拼音",
        isCommand: true,
        isWide: true,
        widthWeight: 1.2
    )
    static let candidateNextPage = Self(
        kind: .candidateNextPage,
        title: "候选",
        systemImageName: nil,
        accessibilityLabel: "显示下一组候选",
        isCommand: true,
        isWide: true,
        widthWeight: 1
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
        kind: .nineKeySpace,
        title: "空格",
        systemImageName: nil,
        accessibilityLabel: "空格",
        isCommand: true,
        isWide: true,
        widthWeight: 1.35
    )
    static let enter = Self(
        kind: .enter,
        title: "回车",
        systemImageName: nil,
        accessibilityLabel: "回车",
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
    static let spacer = Self(
        kind: .spacer,
        title: nil,
        systemImageName: nil,
        accessibilityLabel: "",
        isCommand: true,
        isWide: true,
        widthWeight: 1
    )
}

private extension KeySpec.Kind {
    var isInteractive: Bool {
        if case .spacer = self {
            return false
        }
        return true
    }
}

private enum StationKeyVisualStyle {
    case letter
    case function
    case space
    case mode
    case returnKey
}

private enum StationKeyboardTheme {
    static let accent = UIColor(hex: 0xE8804A)
    static let accentDark = UIColor(hex: 0xD98F31)
    static let trayTop = UIColor(hex: 0x221B15)
    static let trayBottom = UIColor(hex: 0x1A1510)
    static let trayBorder = UIColor(hex: 0x2E261D)
    static let letterKeyTop = UIColor(hex: 0x3F382F)
    static let letterKeyBottom = UIColor(hex: 0x332E27)
    static let functionKey = UIColor(hex: 0x2B241C)
    static let spaceKeyTop = UIColor(hex: 0x463D32)
    static let spaceKeyBottom = UIColor(hex: 0x39322A)
    static let modeKey = UIColor(hex: 0x332A20)
    static let primaryText = UIColor(hex: 0xF3EDE3)
    static let candidateText = UIColor(hex: 0xD8CFC2)
    static let secondaryText = UIColor(hex: 0xD8D0C4)
    static let weakText = UIColor(hex: 0x9A9084)
    static let toolText = UIColor(hex: 0xB3A99B)
    static let divider = UIColor(hex: 0x3A3025)
    static let returnText = UIColor(hex: 0x231703)
}

private final class NineKeyPunctuationPopupView: UIView {
    private static let options = ["！", "？", "。", "，"]
    private let labels: [UILabel]
    private var selectedIndex = options.count - 1

    override var intrinsicContentSize: CGSize {
        CGSize(width: 58, height: CGFloat(Self.options.count * 40))
    }

    var selectedPunctuation: String {
        Self.options[selectedIndex]
    }

    init() {
        labels = Self.options.map { punctuation in
            let label = UILabel()
            label.text = punctuation
            label.font = UIFont.systemFont(ofSize: 21, weight: .medium)
            label.textAlignment = .center
            label.textColor = StationKeyboardTheme.primaryText
            return label
        }
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        backgroundColor = UIColor(hex: 0x4A433B, alpha: 0.98)
        layer.cornerRadius = 9
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = StationKeyboardTheme.divider.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)

        let stack = UIStackView(arrangedSubviews: labels)
        stack.axis = .vertical
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        applySelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(upwardDistance: CGFloat) {
        let step = min(Self.options.count - 1, max(0, Int((upwardDistance + 14) / 38)))
        selectedIndex = Self.options.count - 1 - step
        applySelection()
    }

    private func applySelection() {
        for (index, label) in labels.enumerated() {
            let selected = index == selectedIndex
            label.backgroundColor = selected ? StationKeyboardTheme.accent : .clear
            label.textColor = selected
                ? StationKeyboardTheme.returnText
                : StationKeyboardTheme.primaryText
            label.layer.cornerRadius = 6
            label.layer.masksToBounds = true
        }
    }
}

private final class CandidateScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        if view is UIControl {
            return true
        }
        return super.touchesShouldCancel(in: view)
    }
}

private final class StationKeyButton: UIButton {
    private let keyStyle: StationKeyVisualStyle
    private let gradientLayer = CAGradientLayer()
    private let centeredImageView = UIImageView()
    var hitTestOutsets = UIEdgeInsets.zero

    var cornerRadius: CGFloat = 6 {
        didSet {
            layer.cornerRadius = cornerRadius
            gradientLayer.cornerRadius = cornerRadius
        }
    }

    var isLatched = false {
        didSet {
            applyStyle()
        }
    }

    init(style: StationKeyVisualStyle) {
        keyStyle = style
        super.init(frame: .zero)

        backgroundColor = .clear
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0

        centeredImageView.contentMode = .scaleAspectFit
        centeredImageView.isUserInteractionEnabled = false
        centeredImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 17,
            weight: .medium
        )
        centeredImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centeredImageView)
        NSLayoutConstraint.activate([
            centeredImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            centeredImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            centeredImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 22),
            centeredImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 22),
        ])
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let hitBounds = bounds.inset(
            by: UIEdgeInsets(
                top: -hitTestOutsets.top,
                left: -hitTestOutsets.left,
                bottom: -hitTestOutsets.bottom,
                right: -hitTestOutsets.right
            )
        )
        return hitBounds.contains(point)
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.72 : 1
            transform = isHighlighted
                ? CGAffineTransform(scaleX: 0.975, y: 0.975)
                : .identity
        }
    }

    func setCenteredImage(_ image: UIImage?) {
        centeredImageView.image = image
        centeredImageView.isHidden = image == nil
    }

    private func applyStyle() {
        let colors: [UIColor]
        let foreground: UIColor
        let borderColor: UIColor?

        if isLatched {
            colors = [StationKeyboardTheme.accent, StationKeyboardTheme.accentDark]
            foreground = StationKeyboardTheme.returnText
            borderColor = nil
        } else {
            switch keyStyle {
            case .letter:
                colors = [StationKeyboardTheme.letterKeyTop, StationKeyboardTheme.letterKeyBottom]
                foreground = StationKeyboardTheme.primaryText
                borderColor = nil
            case .function:
                colors = [StationKeyboardTheme.functionKey, StationKeyboardTheme.functionKey]
                foreground = StationKeyboardTheme.secondaryText
                borderColor = nil
            case .space:
                colors = [StationKeyboardTheme.spaceKeyTop, StationKeyboardTheme.spaceKeyBottom]
                foreground = StationKeyboardTheme.weakText
                borderColor = nil
            case .mode:
                colors = [StationKeyboardTheme.modeKey, StationKeyboardTheme.modeKey]
                foreground = StationKeyboardTheme.accent
                borderColor = StationKeyboardTheme.accent.withAlphaComponent(0.55)
            case .returnKey:
                colors = [StationKeyboardTheme.accent, StationKeyboardTheme.accentDark]
                foreground = StationKeyboardTheme.returnText
                borderColor = nil
            }
        }

        gradientLayer.colors = colors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.borderColor = borderColor?.cgColor
        layer.borderWidth = borderColor == nil ? 0 : 1
        tintColor = foreground
        centeredImageView.tintColor = foreground
        setTitleColor(foreground, for: .normal)
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
