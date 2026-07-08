import Cocoa

private enum StationTheme {
    static let windowBackground = NSColor(srgbRed: 0x13 / 255, green: 0x1A / 255, blue: 0x26 / 255, alpha: 1)
    static let cardBackground = NSColor(srgbRed: 0x1B / 255, green: 0x24 / 255, blue: 0x34 / 255, alpha: 1)
    static let pathField = NSColor(srgbRed: 0x10 / 255, green: 0x16 / 255, blue: 0x1F / 255, alpha: 1)
    static let border = NSColor(srgbRed: 0x2A / 255, green: 0x35 / 255, blue: 0x47 / 255, alpha: 1)
    static let divider = NSColor(srgbRed: 0x23 / 255, green: 0x2E / 255, blue: 0x41 / 255, alpha: 1)
    static let lampYellow = NSColor(srgbRed: 0xF0 / 255, green: 0xB2 / 255, blue: 0x4E / 255, alpha: 1)
    static let lampYellowHover = NSColor(srgbRed: 0xFF / 255, green: 0xC4 / 255, blue: 0x64 / 255, alpha: 1)
    static let lampYellowPressed = NSColor(srgbRed: 0xD9 / 255, green: 0x9C / 255, blue: 0x3E / 255, alpha: 1)
    static let onLamp = NSColor(srgbRed: 0x3A / 255, green: 0x26 / 255, blue: 0x05 / 255, alpha: 1)
    static let badgeBackground = NSColor(srgbRed: 0x24 / 255, green: 0x1E / 255, blue: 0x12 / 255, alpha: 1)
    static let toggleOffTrack = NSColor(srgbRed: 0x27 / 255, green: 0x31 / 255, blue: 0x3F / 255, alpha: 1)
    static let toggleOffKnob = NSColor(srgbRed: 0x7C / 255, green: 0x88 / 255, blue: 0x9B / 255, alpha: 1)
    static let textPrimary = NSColor(srgbRed: 0xF2 / 255, green: 0xED / 255, blue: 0xE3 / 255, alpha: 1)
    static let textStep = NSColor(srgbRed: 0xD9 / 255, green: 0xDF / 255, blue: 0xE9 / 255, alpha: 1)
    static let textSecondary = NSColor(srgbRed: 0x93 / 255, green: 0xA0 / 255, blue: 0xB4 / 255, alpha: 1)
    static let textFaint = NSColor(srgbRed: 0x5C / 255, green: 0x68 / 255, blue: 0x78 / 255, alpha: 1)
    static let ghostHover = NSColor(srgbRed: 0x20 / 255, green: 0x2B / 255, blue: 0x3D / 255, alpha: 1)
    static let ghostPressed = NSColor(srgbRed: 0x18 / 255, green: 0x21 / 255, blue: 0x31 / 255, alpha: 1)
}

private final class StationToggle: NSView {
    var onToggle: (() -> Void)?

    var isOn = false {
        didSet {
            updateAppearance()
        }
    }

    var isEnabledToggle = true {
        didSet {
            updateAppearance()
        }
    }

    private let trackLayer = CALayer()
    private let knobLayer = CALayer()
    private let diameter: CGFloat = 20
    private let edge: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        trackLayer.cornerRadius = 13
        knobLayer.cornerRadius = diameter / 2
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(knobLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        updateAppearance()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        let y = (bounds.height - diameter) / 2
        let x = isOn ? bounds.width - diameter - edge : edge
        knobLayer.frame = CGRect(x: x, y: y, width: diameter, height: diameter)
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabledToggle else {
            return
        }
        isOn.toggle()
        onToggle?()
    }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.backgroundColor = (isOn ? StationTheme.lampYellow : StationTheme.toggleOffTrack).cgColor
        knobLayer.backgroundColor = (isOn ? StationTheme.onLamp : StationTheme.toggleOffKnob).cgColor
        layer?.opacity = isEnabledToggle ? 1 : 0.4
        CATransaction.commit()
        needsLayout = true
        setAccessibilityValue(isOn)
    }
}

private final class StationButton: NSButton {
    private let normalBackground: NSColor
    private let hoverBackground: NSColor
    private let pressedBackground: NSColor
    private let titleColor: NSColor
    private let borderColor: NSColor?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressing = false

    init(
        title: String,
        target: AnyObject,
        action: Selector,
        normalBackground: NSColor,
        hoverBackground: NSColor,
        pressedBackground: NSColor,
        titleColor: NSColor,
        borderColor: NSColor? = nil
    ) {
        self.normalBackground = normalBackground
        self.hoverBackground = hoverBackground
        self.pressedBackground = pressedBackground
        self.titleColor = titleColor
        self.borderColor = borderColor
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = borderColor == nil ? 0 : 1
        layer?.borderColor = borderColor?.cgColor
        font = .systemFont(ofSize: 14, weight: .medium)
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressing = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
        updateAppearance()
        super.mouseDown(with: event)
        isPressing = false
        updateAppearance()
    }

    private func updateAppearance() {
        let background = isPressing ? pressedBackground : (isHovering ? hoverBackground : normalBackground)
        layer?.backgroundColor = background.cgColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: titleColor,
                .font: font ?? NSFont.systemFont(ofSize: 14, weight: .medium),
            ]
        )
    }
}

final class PrivatePinyinPreferencesWindowController: NSWindowController {
    static let shared = PrivatePinyinPreferencesWindowController()

    private let strictPrivacyToggle = StationToggle()
    private let predictionToggle = StationToggle()
    private let learningToggle = StationToggle()
    private let learningTitleLabel = NSTextField(labelWithString: "用户学习")
    private let learningDetailLabel = NSTextField(labelWithString: "记住你常选的词，逐渐排得更靠前")
    private let settingsPathLabel = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 452),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "猫栈拼音偏好设置"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = StationTheme.windowBackground
        super.init(window: window)
        buildContent()
        reloadFromSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showPreferences() {
        reloadFromSettings()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = StationTheme.windowBackground.cgColor

        strictPrivacyToggle.onToggle = { [weak self] in self?.commitSettings() }
        predictionToggle.onToggle = { [weak self] in self?.commitSettings() }
        learningToggle.onToggle = { [weak self] in self?.commitSettings() }

        let brandRow = makeBrandRow()
        let card = makeSettingsCard()
        let pathSection = makePathSection()
        let footer = makeFooterRow()

        let topInset: CGFloat = 24
        let sideInset: CGFloat = 26
        let bottomInset: CGFloat = 24

        let root = NSStackView(views: [brandRow, card, pathSection, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideInset),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -sideInset),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: topInset),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -bottomInset),
            brandRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            card.widthAnchor.constraint(equalTo: root.widthAnchor),
            pathSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])

        root.layoutSubtreeIfNeeded()
        let fitted = topInset + root.fittingSize.height + bottomInset
        window?.setContentSize(NSSize(width: 468, height: ceil(fitted)))
    }

    private func makeBrandRow() -> NSView {
        let mark = label(
            "拼",
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: StationTheme.onLamp
        )
        mark.alignment = .center

        let markBox = roundedBox(background: StationTheme.lampYellow, cornerRadius: 10)
        mark.translatesAutoresizingMaskIntoConstraints = false
        markBox.addSubview(mark)
        NSLayoutConstraint.activate([
            markBox.widthAnchor.constraint(equalToConstant: 40),
            markBox.heightAnchor.constraint(equalToConstant: 40),
            mark.centerXAnchor.constraint(equalTo: markBox.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: markBox.centerYAnchor),
        ])

        let name = label(
            "猫栈拼音",
            font: .systemFont(ofSize: 13, weight: .medium),
            color: StationTheme.textPrimary
        )
        let caption = label(
            "station cat · input method",
            font: .systemFont(ofSize: 11, weight: .regular),
            color: StationTheme.textSecondary
        )

        let nameColumn = NSStackView(views: [name, caption])
        nameColumn.orientation = .vertical
        nameColumn.alignment = .leading
        nameColumn.spacing = 1

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [markBox, nameColumn, spacer, paddedBadge(text: "preferences")])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeSettingsCard() -> NSView {
        let strictRow = makeSettingRow(
            titleLabel: label("严格隐私模式", font: .systemFont(ofSize: 14, weight: .medium), color: StationTheme.textPrimary),
            detailLabel: label("只在本机计算，开启后会自动关闭「用户学习」", font: .systemFont(ofSize: 12, weight: .regular), color: StationTheme.textSecondary),
            toggle: strictPrivacyToggle
        )
        let predictionRow = makeSettingRow(
            titleLabel: label("显示预测候选", font: .systemFont(ofSize: 14, weight: .medium), color: StationTheme.textPrimary),
            detailLabel: label("在候选栏里显示下一词预测", font: .systemFont(ofSize: 12, weight: .regular), color: StationTheme.textSecondary),
            toggle: predictionToggle
        )
        learningTitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        learningDetailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        let learningRow = makeSettingRow(
            titleLabel: learningTitleLabel,
            detailLabel: learningDetailLabel,
            toggle: learningToggle
        )

        let stack = NSStackView(views: [strictRow, hairline(), predictionRow, hairline(), learningRow])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = roundedBox(background: StationTheme.cardBackground, cornerRadius: 12, border: StationTheme.border)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2),
        ])
        return card
    }

    private func makeSettingRow(titleLabel: NSTextField, detailLabel: NSTextField, toggle: StationToggle) -> NSView {
        for field in [titleLabel, detailLabel] {
            field.backgroundColor = .clear
            field.isBezeled = false
            field.isEditable = false
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        titleLabel.textColor = StationTheme.textPrimary
        detailLabel.textColor = StationTheme.textSecondary

        let textColumn = NSStackView(views: [titleLabel, detailLabel])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 3

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [textColumn, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
        return row
    }

    private func makePathSection() -> NSView {
        let caption = label("设置文件", font: .systemFont(ofSize: 11, weight: .regular), color: StationTheme.textFaint)

        let icon = NSImageView()
        if #available(macOS 11.0, *) {
            icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "设置文件")
        }
        icon.contentTintColor = StationTheme.lampYellow
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true

        settingsPathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        settingsPathLabel.textColor = StationTheme.textSecondary
        settingsPathLabel.backgroundColor = .clear
        settingsPathLabel.isBezeled = false
        settingsPathLabel.isEditable = false
        settingsPathLabel.lineBreakMode = .byTruncatingMiddle
        settingsPathLabel.cell?.usesSingleLineMode = true
        settingsPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        settingsPathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let fieldRow = NSStackView(views: [icon, settingsPathLabel])
        fieldRow.orientation = .horizontal
        fieldRow.alignment = .centerY
        fieldRow.spacing = 9
        fieldRow.translatesAutoresizingMaskIntoConstraints = false

        let field = roundedBox(background: StationTheme.pathField, cornerRadius: 8, border: StationTheme.border)
        field.addSubview(fieldRow)
        NSLayoutConstraint.activate([
            fieldRow.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 12),
            fieldRow.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -12),
            fieldRow.topAnchor.constraint(equalTo: field.topAnchor, constant: 9),
            fieldRow.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -9),
        ])

        let column = NSStackView(views: [caption, field])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 7
        column.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    private func makeFooterRow() -> NSView {
        let openButton = StationButton(
            title: "打开设置文件",
            target: self,
            action: #selector(openSettingsFile(_:)),
            normalBackground: StationTheme.lampYellow,
            hoverBackground: StationTheme.lampYellowHover,
            pressedBackground: StationTheme.lampYellowPressed,
            titleColor: StationTheme.onLamp
        )
        openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true

        let reloadButton = StationButton(
            title: "重新载入",
            target: self,
            action: #selector(reloadButtonPressed(_:)),
            normalBackground: .clear,
            hoverBackground: StationTheme.ghostHover,
            pressedBackground: StationTheme.ghostPressed,
            titleColor: StationTheme.textStep,
            borderColor: StationTheme.border
        )
        reloadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true

        let buttons = NSStackView(views: [openButton, reloadButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 11

        let signatureFont = NSFontManager.shared.convert(.systemFont(ofSize: 11, weight: .regular), toHaveTrait: .italicFontMask)
        let signature = label("a small station, still lit at night", font: signatureFont, color: StationTheme.textFaint)
        signature.alignment = .right

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [buttons, spacer, signature])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func reloadFromSettings() {
        _ = PrivatePinyinSettingsStore.ensureSettingsFile()
        let settings = PrivatePinyinSettingsStore.settingsSnapshot()
        let strictPrivacy = settings["strict_privacy_mode"] as? Bool ?? false
        strictPrivacyToggle.isOn = strictPrivacy
        predictionToggle.isOn = settings["enable_prediction"] as? Bool ?? true
        let learning = settings["enable_user_learning"] as? Bool ?? true
        learningToggle.isOn = strictPrivacy ? false : learning
        setLearningEnabled(!strictPrivacy)

        let path = PrivatePinyinSettingsStore.settingsURL.path
        settingsPathLabel.stringValue = path
        settingsPathLabel.toolTip = path
    }

    private func setLearningEnabled(_ enabled: Bool) {
        learningToggle.isEnabledToggle = enabled
        learningTitleLabel.textColor = enabled ? StationTheme.textPrimary : StationTheme.textFaint
        learningDetailLabel.textColor = enabled ? StationTheme.textSecondary : StationTheme.textFaint
    }

    private func commitSettings() {
        let strictPrivacy = strictPrivacyToggle.isOn
        let ok = PrivatePinyinSettingsStore.updateSettings { settings in
            settings["strict_privacy_mode"] = strictPrivacy
            settings["enable_prediction"] = predictionToggle.isOn
            settings["enable_user_learning"] = strictPrivacy ? false : learningToggle.isOn
        }

        if ok {
            reloadFromSettings()
            NotificationCenter.default.post(name: .privatePinyinSettingsChanged, object: self)
        } else {
            reloadFromSettings()
            showAlert("无法更新设置。")
        }
    }

    @objc private func openSettingsFile(_ sender: Any?) {
        guard PrivatePinyinSettingsStore.ensureSettingsFile() != nil else {
            showAlert("无法创建设置文件。")
            return
        }
        NSWorkspace.shared.open(PrivatePinyinSettingsStore.settingsURL)
    }

    @objc private func reloadButtonPressed(_ sender: Any?) {
        reloadFromSettings()
        NotificationCenter.default.post(name: .privatePinyinSettingsChanged, object: self)
    }

    private func showAlert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    private func paddedBadge(text: String) -> NSView {
        let badgeLabel = label(text, font: .systemFont(ofSize: 11, weight: .regular), color: StationTheme.lampYellow)
        let box = roundedBox(background: StationTheme.badgeBackground, cornerRadius: 11, border: StationTheme.border)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
            badgeLabel.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
            badgeLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            badgeLabel.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
        ])
        return box
    }

    private func hairline() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = StationTheme.divider.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func roundedBox(background: NSColor, cornerRadius: CGFloat, border: NSColor? = nil) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer?.backgroundColor = background.cgColor
        view.layer?.cornerRadius = cornerRadius
        if let border {
            view.layer?.borderColor = border.cgColor
            view.layer?.borderWidth = 1
        }
        return view
    }

    private func label(_ value: String, font: NSFont, color: NSColor) -> NSTextField {
        let text = NSTextField(labelWithString: value)
        text.font = font
        text.textColor = color
        text.backgroundColor = .clear
        text.setContentCompressionResistancePriority(.required, for: .vertical)
        return text
    }
}

extension Notification.Name {
    static let privatePinyinSettingsChanged = Notification.Name("PrivatePinyinSettingsChanged")
}
