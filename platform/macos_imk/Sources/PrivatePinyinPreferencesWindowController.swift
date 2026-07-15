import Cocoa

private enum StationTheme {
    static let windowBackground = NSColor(srgbRed: 0x14 / 255, green: 0x1B / 255, blue: 0x2D / 255, alpha: 1)
    static let brandBackground = NSColor(srgbRed: 0x25 / 255, green: 0x2D / 255, blue: 0x47 / 255, alpha: 1)
    static let cardBackground = NSColor(srgbRed: 0x1F / 255, green: 0x29 / 255, blue: 0x40 / 255, alpha: 1)
    static let pathField = NSColor(srgbRed: 0x21 / 255, green: 0x2B / 255, blue: 0x42 / 255, alpha: 1)
    static let border = NSColor(srgbRed: 0x31 / 255, green: 0x3B / 255, blue: 0x54 / 255, alpha: 1)
    static let divider = NSColor(srgbRed: 0x2B / 255, green: 0x35 / 255, blue: 0x4D / 255, alpha: 1)
    static let dot = NSColor(srgbRed: 0x2A / 255, green: 0x34 / 255, blue: 0x4A / 255, alpha: 0.38)
    static let tape = NSColor(srgbRed: 0x9A / 255, green: 0x70 / 255, blue: 0x3C / 255, alpha: 0.86)
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

private final class StationBoardBackgroundView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        StationTheme.windowBackground.setFill()
        dirtyRect.fill()

        StationTheme.dot.setFill()
        let spacing: CGFloat = 16
        let radius: CGFloat = 0.8
        var y = floor(dirtyRect.minY / spacing) * spacing
        while y <= dirtyRect.maxY {
            var x = floor(dirtyRect.minX / spacing) * spacing
            while x <= dirtyRect.maxX {
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: radius * 2, height: radius * 2)).fill()
                x += spacing
            }
            y += spacing
        }
    }
}

private final class StationTapeView: NSView {
    init(angle: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.backgroundColor = StationTheme.tape.cgColor
        layer?.cornerRadius = 2
        frameCenterRotation = angle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
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
    private let diameter: CGFloat = 22
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
        widthAnchor.constraint(equalToConstant: 48).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        trackLayer.cornerRadius = 14
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
        layer?.cornerRadius = 9
        layer?.borderWidth = borderColor == nil ? 0 : 1
        layer?.borderColor = borderColor?.cgColor
        font = .systemFont(ofSize: 15, weight: .semibold)
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true
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

    func setStationTitle(_ value: String) {
        title = value
        updateAppearance()
    }

    private func updateAppearance() {
        let background = isPressing ? pressedBackground : (isHovering ? hoverBackground : normalBackground)
        layer?.backgroundColor = background.cgColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: titleColor,
                .font: font ?? NSFont.systemFont(ofSize: 15, weight: .semibold),
            ]
        )
    }
}

final class PrivatePinyinPreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PrivatePinyinPreferencesWindowController()

    private static let boardWidth: CGFloat = 780
    private static let initialBoardHeight: CGFloat = 748
    private static let defaultBoardScale: CGFloat = 0.86
    private static let minimumBoardScale: CGFloat = 0.72
    private static let maximumBoardScale: CGFloat = 1

    private let strictPrivacyToggle = StationToggle()
    private let predictionToggle = StationToggle()
    private let learningToggle = StationToggle()
    private let learningTitleLabel = NSTextField(labelWithString: "用户学习")
    private let learningDetailLabel = NSTextField(labelWithString: "记住你常选的词，像猫记得饭点一样准。")
    private let settingsPathLabel = NSTextField(labelWithString: "")
    private let automaticUpdateToggle = StationToggle()
    private let automaticUpdateDetailLabel = NSTextField(labelWithString: "每天最多读取一次固定的公开版本清单，不上传输入内容。")
    private let updateStatusLabel = NSTextField(labelWithString: "尚未检查更新")
    private let updateDetailLabel = NSTextField(labelWithString: "输入功能始终不依赖更新服务。")
    private let boardScrollView = NSScrollView(frame: .zero)
    private let boardView = StationBoardBackgroundView(
        frame: NSRect(x: 0, y: 0, width: boardWidth, height: initialBoardHeight)
    )
    private var boardDesignSize = NSSize(width: boardWidth, height: initialBoardHeight)
    private var checkUpdateButton: StationButton?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.boardWidth, height: Self.initialBoardHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "猫栈拼音偏好设置"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = StationTheme.windowBackground
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = StationTheme.windowBackground.cgColor
        window.contentView = contentView
        super.init(window: window)
        window.delegate = self
        buildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStateChanged(_:)),
            name: .privatePinyinUpdateStateChanged,
            object: nil
        )
        reloadFromSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showPreferences() {
        reloadFromSettings()
        PrivatePinyinUpdateController.shared.scheduleAutomaticCheck()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        boardScrollView.translatesAutoresizingMaskIntoConstraints = false
        boardScrollView.borderType = .noBorder
        boardScrollView.drawsBackground = false
        boardScrollView.hasHorizontalScroller = false
        boardScrollView.hasVerticalScroller = false
        boardScrollView.horizontalScrollElasticity = .none
        boardScrollView.verticalScrollElasticity = .none
        boardScrollView.allowsMagnification = true
        boardScrollView.minMagnification = Self.minimumBoardScale
        boardScrollView.maxMagnification = Self.maximumBoardScale
        boardScrollView.documentView = boardView
        contentView.addSubview(boardScrollView)
        NSLayoutConstraint.activate([
            boardScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            boardScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            boardScrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            boardScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        strictPrivacyToggle.onToggle = { [weak self] in self?.commitSettings() }
        predictionToggle.onToggle = { [weak self] in self?.commitSettings() }
        learningToggle.onToggle = { [weak self] in self?.commitSettings() }
        automaticUpdateToggle.onToggle = { [weak self] in self?.automaticUpdateSettingChanged() }
        strictPrivacyToggle.setAccessibilityLabel("严格隐私模式")
        predictionToggle.setAccessibilityLabel("显示预测候选")
        learningToggle.setAccessibilityLabel("用户学习")
        automaticUpdateToggle.setAccessibilityLabel("自动检查更新")

        let topRail = makeTopRail()
        let brandCard = makeBrandCard()
        let privacyCard = makePrivacyCard()
        let settingsGrid = makeSettingsGrid()
        let pathSection = makePathSection()
        let versionSection = makeVersionSection()
        let footer = makeFooterRow()

        let topInset: CGFloat = 18
        let sideInset: CGFloat = 28
        let bottomInset: CGFloat = 22

        let root = NSStackView(views: [
            topRail,
            hairline(),
            brandCard,
            privacyCard,
            settingsGrid,
            pathSection,
            versionSection,
            footer,
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        boardView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: boardView.leadingAnchor, constant: sideInset),
            root.trailingAnchor.constraint(equalTo: boardView.trailingAnchor, constant: -sideInset),
            root.topAnchor.constraint(equalTo: boardView.topAnchor, constant: topInset),
            root.bottomAnchor.constraint(lessThanOrEqualTo: boardView.bottomAnchor, constant: -bottomInset),
            topRail.widthAnchor.constraint(equalTo: root.widthAnchor),
            brandCard.widthAnchor.constraint(equalTo: root.widthAnchor),
            privacyCard.widthAnchor.constraint(equalTo: root.widthAnchor),
            settingsGrid.widthAnchor.constraint(equalTo: root.widthAnchor),
            pathSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            versionSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])

        boardView.layoutSubtreeIfNeeded()
        let fitted = topInset + root.fittingSize.height + bottomInset
        boardDesignSize = NSSize(width: Self.boardWidth, height: ceil(fitted))
        boardView.frame = NSRect(origin: .zero, size: boardDesignSize)

        window?.contentAspectRatio = boardDesignSize
        window?.contentMinSize = scaledBoardSize(Self.minimumBoardScale)
        window?.contentMaxSize = scaledBoardSize(Self.maximumBoardScale)
        window?.preservesContentDuringLiveResize = true
        window?.setContentSize(scaledBoardSize(Self.defaultBoardScale))
        contentView.layoutSubtreeIfNeeded()
        updateBoardScale()
    }

    func windowDidResize(_ notification: Notification) {
        updateBoardScale()
    }

    private func scaledBoardSize(_ scale: CGFloat) -> NSSize {
        NSSize(
            width: round(boardDesignSize.width * scale),
            height: round(boardDesignSize.height * scale)
        )
    }

    private func updateBoardScale() {
        guard boardDesignSize.width > 0, boardDesignSize.height > 0 else {
            return
        }

        let viewport = boardScrollView.contentSize
        guard viewport.width > 0, viewport.height > 0 else {
            return
        }

        let fittedScale = min(
            viewport.width / boardDesignSize.width,
            viewport.height / boardDesignSize.height
        )
        let scale = min(max(fittedScale, Self.minimumBoardScale), Self.maximumBoardScale)
        if abs(boardScrollView.magnification - scale) > 0.001 {
            boardScrollView.setMagnification(
                scale,
                centeredAt: NSPoint(x: boardDesignSize.width / 2, y: boardDesignSize.height / 2)
            )
        }
        boardScrollView.contentView.scroll(to: .zero)
        boardScrollView.reflectScrolledClipView(boardScrollView.contentView)
    }

    private func makeTopRail() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stationBoard = trackedLabel(
            "STATION BOARD",
            font: .monospacedSystemFont(ofSize: 11, weight: .semibold),
            color: StationTheme.textFaint,
            kerning: 3
        )

        let row = NSStackView(views: [spacer, stationBoard])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return row
    }

    private func makeBrandCard() -> NSView {
        let mark = label(
            "拼",
            font: .systemFont(ofSize: 28, weight: .bold),
            color: StationTheme.onLamp
        )
        mark.alignment = .center

        let markBox = roundedBox(background: StationTheme.lampYellow, cornerRadius: 14)
        mark.translatesAutoresizingMaskIntoConstraints = false
        markBox.addSubview(mark)
        NSLayoutConstraint.activate([
            markBox.widthAnchor.constraint(equalToConstant: 64),
            markBox.heightAnchor.constraint(equalToConstant: 64),
            mark.centerXAnchor.constraint(equalTo: markBox.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: markBox.centerYAnchor),
        ])

        let name = label(
            "猫栈拼音偏好设置",
            font: .systemFont(ofSize: 24, weight: .bold),
            color: StationTheme.textPrimary
        )
        let caption = label(
            "station cat · input method",
            font: .monospacedSystemFont(ofSize: 13, weight: .medium),
            color: StationTheme.textSecondary
        )

        let nameColumn = NSStackView(views: [name, caption])
        nameColumn.orientation = .vertical
        nameColumn.alignment = .leading
        nameColumn.spacing = 5

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [markBox, nameColumn, spacer, paddedBadge(text: "CAT")])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false

        let card = roundedBox(background: StationTheme.brandBackground, cornerRadius: 8)
        card.addSubview(row)
        let tape = StationTapeView(angle: -5)
        card.addSubview(tape)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
            tape.widthAnchor.constraint(equalToConstant: 72),
            tape.heightAnchor.constraint(equalToConstant: 16),
            tape.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 32),
            tape.topAnchor.constraint(equalTo: card.topAnchor, constant: -7),
        ])
        return card
    }

    private func makePrivacyCard() -> NSView {
        let card = makeSettingCard(
            tag: "PRIVACY",
            titleLabel: label("严格隐私模式", font: .systemFont(ofSize: 17, weight: .semibold), color: StationTheme.textPrimary),
            detailLabel: wrappingLabel(
                "只在本机计算，开启后会自动关闭「用户学习」。",
                font: .systemFont(ofSize: 13, weight: .regular),
                color: StationTheme.textSecondary
            ),
            toggle: strictPrivacyToggle,
            minimumHeight: 118
        )
        let tape = StationTapeView(angle: 3)
        card.addSubview(tape)
        NSLayoutConstraint.activate([
            tape.widthAnchor.constraint(equalToConstant: 62),
            tape.heightAnchor.constraint(equalToConstant: 15),
            tape.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            tape.topAnchor.constraint(equalTo: card.topAnchor, constant: -6),
        ])
        return card
    }

    private func makeSettingsGrid() -> NSView {
        let predictionCard = makeSettingCard(
            tag: "PREDICT",
            titleLabel: label("显示预测候选", font: .systemFont(ofSize: 17, weight: .semibold), color: StationTheme.textPrimary),
            detailLabel: wrappingLabel(
                "在候选栏里，先探个头再决定要不要蹦出来。",
                font: .systemFont(ofSize: 13, weight: .regular),
                color: StationTheme.textSecondary
            ),
            toggle: predictionToggle,
            minimumHeight: 142
        )
        learningTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        learningDetailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        learningDetailLabel.maximumNumberOfLines = 2
        learningDetailLabel.lineBreakMode = .byWordWrapping
        learningDetailLabel.cell?.wraps = true
        let learningCard = makeSettingCard(
            tag: "LEARN",
            titleLabel: learningTitleLabel,
            detailLabel: learningDetailLabel,
            toggle: learningToggle,
            minimumHeight: 142
        )

        let row = NSStackView(views: [predictionCard, learningCard])
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        predictionCard.heightAnchor.constraint(equalTo: learningCard.heightAnchor).isActive = true
        return row
    }

    private func makeSettingCard(
        tag: String,
        titleLabel: NSTextField,
        detailLabel: NSTextField,
        toggle: StationToggle,
        minimumHeight: CGFloat
    ) -> NSView {
        for field in [titleLabel, detailLabel] {
            field.backgroundColor = .clear
            field.isBezeled = false
            field.isEditable = false
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        titleLabel.textColor = StationTheme.textPrimary
        detailLabel.textColor = StationTheme.textSecondary

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let titleRow = NSStackView(views: [titleLabel, spacer, toggle])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 14

        let content = NSStackView(views: [paddedBadge(text: tag), titleRow, detailLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        titleRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        detailLabel.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        let card = roundedBox(background: StationTheme.cardBackground, cornerRadius: 12)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight),
        ])
        return card
    }

    private func makePathSection() -> NSView {
        let caption = label("设置文件", font: .systemFont(ofSize: 12, weight: .medium), color: StationTheme.textFaint)

        let icon = NSImageView()
        if #available(macOS 11.0, *) {
            icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "设置文件")
        }
        icon.contentTintColor = StationTheme.textStep
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true

        settingsPathLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        settingsPathLabel.textColor = StationTheme.textStep
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
        fieldRow.spacing = 12
        fieldRow.translatesAutoresizingMaskIntoConstraints = false

        let field = roundedBox(background: StationTheme.pathField, cornerRadius: 10)
        field.addSubview(fieldRow)
        NSLayoutConstraint.activate([
            fieldRow.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 16),
            fieldRow.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -16),
            fieldRow.topAnchor.constraint(equalTo: field.topAnchor, constant: 12),
            fieldRow.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -12),
        ])

        let column = NSStackView(views: [hairline(), caption, field])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 9
        column.translatesAutoresizingMaskIntoConstraints = false
        column.arrangedSubviews[0].widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        field.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    private func makeVersionSection() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let version = label(
            bundleVersionText,
            font: .monospacedSystemFont(ofSize: 12, weight: .semibold),
            color: StationTheme.lampYellow
        )
        let header = NSStackView(views: [paddedBadge(text: "VERSION"), spacer, version])
        header.orientation = .horizontal
        header.alignment = .centerY

        let title = label("本次更新", font: .systemFont(ofSize: 15, weight: .semibold), color: StationTheme.textPrimary)
        let notes = wrappingLabel(
            releaseNotesText,
            font: .systemFont(ofSize: 12, weight: .regular),
            color: StationTheme.textSecondary
        )
        notes.maximumNumberOfLines = 3

        updateStatusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        updateStatusLabel.textColor = StationTheme.textPrimary
        updateDetailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        updateDetailLabel.textColor = StationTheme.textSecondary
        updateDetailLabel.maximumNumberOfLines = 2
        updateDetailLabel.lineBreakMode = .byWordWrapping
        let statusColumn = NSStackView(views: [updateStatusLabel, updateDetailLabel])
        statusColumn.orientation = .vertical
        statusColumn.alignment = .leading
        statusColumn.spacing = 4

        let statusSpacer = NSView()
        statusSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let checkButton = StationButton(
            title: "检查更新",
            target: self,
            action: #selector(checkUpdateButtonPressed(_:)),
            normalBackground: .clear,
            hoverBackground: StationTheme.ghostHover,
            pressedBackground: StationTheme.ghostPressed,
            titleColor: StationTheme.textStep,
            borderColor: StationTheme.border
        )
        checkButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        checkUpdateButton = checkButton
        let statusRow = NSStackView(views: [statusColumn, statusSpacer, checkButton])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 14

        let autoTitle = label("自动检查更新", font: .systemFont(ofSize: 14, weight: .semibold), color: StationTheme.textPrimary)
        automaticUpdateDetailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        automaticUpdateDetailLabel.textColor = StationTheme.textSecondary
        automaticUpdateDetailLabel.maximumNumberOfLines = 2
        automaticUpdateDetailLabel.lineBreakMode = .byWordWrapping
        let autoColumn = NSStackView(views: [autoTitle, automaticUpdateDetailLabel])
        autoColumn.orientation = .vertical
        autoColumn.alignment = .leading
        autoColumn.spacing = 4
        let autoSpacer = NSView()
        autoSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let autoRow = NSStackView(views: [autoColumn, autoSpacer, automaticUpdateToggle])
        autoRow.orientation = .horizontal
        autoRow.alignment = .centerY
        autoRow.spacing = 14

        let divider = hairline()

        let content = NSStackView(views: [header, title, notes, divider, statusRow, autoRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        notes.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        divider.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        statusRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        autoRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        let card = roundedBox(background: StationTheme.cardBackground, cornerRadius: 12)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 236),
        ])
        return card
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
        openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 142).isActive = true

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
        reloadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true

        let buttons = NSStackView(views: [openButton, reloadButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 11

        let signatureFont = NSFontManager.shared.convert(.systemFont(ofSize: 12, weight: .regular), toHaveTrait: .italicFontMask)
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

    private var bundleVersionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版本"
        return "版本 \(version)"
    }

    private var releaseNotesText: String {
        if let url = Bundle.main.url(forResource: "ReleaseNotes.zh-Hans", withExtension: "txt"),
           let value = try? String(contentsOf: url, encoding: .utf8)
        {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "新增连续拼音与简拼输入；完善本地用户联想学习；优化词库覆盖、候选排序和跨平台输入体验。"
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
        automaticUpdateToggle.isOn = PrivatePinyinUpdateController.shared.automaticChecksEnabled
        automaticUpdateToggle.isEnabledToggle = !strictPrivacy
        automaticUpdateDetailLabel.stringValue = strictPrivacy
            ? "严格隐私模式下后台检查已暂停；手动检查会先征求确认。"
            : "每天最多读取一次固定的公开版本清单，不上传输入内容。"
        automaticUpdateDetailLabel.textColor = strictPrivacy ? StationTheme.textFaint : StationTheme.textSecondary
        refreshUpdatePresentation()

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

    @objc private func checkUpdateButtonPressed(_ sender: Any?) {
        PrivatePinyinUpdateController.shared.checkOrPresentUpdate(presentingWindow: window)
    }

    @objc private func updateStateChanged(_ notification: Notification) {
        refreshUpdatePresentation()
    }

    private func automaticUpdateSettingChanged() {
        PrivatePinyinUpdateController.shared.setAutomaticChecksEnabled(automaticUpdateToggle.isOn)
        reloadFromSettings()
    }

    private func refreshUpdatePresentation() {
        let state = PrivatePinyinUpdateController.shared.state
        checkUpdateButton?.isEnabled = true
        switch state {
        case .idle:
            checkUpdateButton?.setStationTitle("检查更新")
            updateStatusLabel.stringValue = "尚未检查更新"
            updateStatusLabel.textColor = StationTheme.textPrimary
            updateDetailLabel.stringValue = "输入功能始终不依赖更新服务。"
        case .checking:
            checkUpdateButton?.setStationTitle("正在检查")
            checkUpdateButton?.isEnabled = false
            updateStatusLabel.stringValue = "正在检查更新..."
            updateStatusLabel.textColor = StationTheme.lampYellow
            updateDetailLabel.stringValue = "正在读取 Station Cat 的固定公开版本清单。"
        case let .upToDate(checkedAt):
            checkUpdateButton?.setStationTitle("再次检查")
            updateStatusLabel.stringValue = "已经是最新版本"
            updateStatusLabel.textColor = StationTheme.textPrimary
            updateDetailLabel.stringValue = "最近检查：\(Self.updateDateFormatter.string(from: checkedAt))"
        case let .updateAvailable(update):
            checkUpdateButton?.setStationTitle("查看更新")
            updateStatusLabel.stringValue = "发现新版本 \(update.manifest.version)"
            updateStatusLabel.textColor = StationTheme.lampYellow
            updateDetailLabel.stringValue = update.manifest.title
        case let .systemUpgradeRequired(update):
            checkUpdateButton?.setStationTitle("查看说明")
            updateStatusLabel.stringValue = "新版本需要 macOS \(update.manifest.minimumMacOSVersion)"
            updateStatusLabel.textColor = StationTheme.lampYellow
            updateDetailLabel.stringValue = "当前系统可以继续使用已安装版本。"
        case let .downloading(_, progress):
            checkUpdateButton?.setStationTitle("取消下载")
            updateStatusLabel.stringValue = "正在下载更新（\(progress)%）"
            updateStatusLabel.textColor = StationTheme.lampYellow
            updateDetailLabel.stringValue = "下载完成后会先在本机执行完整安全验证。"
        case .verifying:
            checkUpdateButton?.setStationTitle("正在验证")
            checkUpdateButton?.isEnabled = false
            updateStatusLabel.stringValue = "正在验证更新包"
            updateStatusLabel.textColor = StationTheme.lampYellow
            updateDetailLabel.stringValue = "正在核对大小、SHA-256、开发者签名和 Apple 公证。"
        case let .readyToInstall(update, _, installerOpened):
            checkUpdateButton?.setStationTitle(installerOpened ? "重新打开" : "打开安装器")
            updateStatusLabel.stringValue = installerOpened ? "系统安装器已打开" : "更新包已通过安全验证"
            updateStatusLabel.textColor = StationTheme.lampYellow
            updateDetailLabel.stringValue = installerOpened
                ? "请在系统安装器中确认安装猫栈拼音 \(update.manifest.version)。"
                : "下一步由 macOS 系统安装器请求你的确认。"
        case let .packageFailed(_, failure):
            checkUpdateButton?.setStationTitle("重试")
            updateStatusLabel.stringValue = "更新已被安全拦截"
            updateStatusLabel.textColor = StationTheme.textPrimary
            updateDetailLabel.stringValue = PrivatePinyinUpdateController.packageFailureSummary(failure)
        case .failed:
            checkUpdateButton?.setStationTitle("重试")
            updateStatusLabel.stringValue = "暂时无法检查更新"
            updateStatusLabel.textColor = StationTheme.textPrimary
            updateDetailLabel.stringValue = "输入功能不受影响，请稍后重试。"
        }
    }

    private static let updateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func showAlert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    private func paddedBadge(text: String) -> NSView {
        let badgeLabel = trackedLabel(
            text,
            font: .monospacedSystemFont(ofSize: 11, weight: .semibold),
            color: StationTheme.lampYellow,
            kerning: 1.5
        )
        let box = roundedBox(background: .clear, cornerRadius: 12, border: StationTheme.lampYellow)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 5),
            badgeLabel.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -5),
            badgeLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            badgeLabel.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
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

    private func wrappingLabel(_ value: String, font: NSFont, color: NSColor) -> NSTextField {
        let text = NSTextField(wrappingLabelWithString: value)
        text.font = font
        text.textColor = color
        text.backgroundColor = .clear
        text.maximumNumberOfLines = 0
        text.lineBreakMode = .byWordWrapping
        text.setContentCompressionResistancePriority(.required, for: .vertical)
        return text
    }

    private func trackedLabel(
        _ value: String,
        font: NSFont,
        color: NSColor,
        kerning: CGFloat
    ) -> NSTextField {
        let text = NSTextField(labelWithString: "")
        text.attributedStringValue = NSAttributedString(
            string: value,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: kerning,
            ]
        )
        text.backgroundColor = .clear
        text.setContentCompressionResistancePriority(.required, for: .vertical)
        return text
    }
}

extension Notification.Name {
    static let privatePinyinSettingsChanged = Notification.Name("PrivatePinyinSettingsChanged")
}
