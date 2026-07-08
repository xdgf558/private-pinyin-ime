import Cocoa

private enum StationTheme {
    static let windowBackground = NSColor(srgbRed: 0x13 / 255, green: 0x1A / 255, blue: 0x26 / 255, alpha: 1)
    static let cardBackground = NSColor(srgbRed: 0x1B / 255, green: 0x24 / 255, blue: 0x34 / 255, alpha: 1)
    static let border = NSColor(srgbRed: 0x2A / 255, green: 0x35 / 255, blue: 0x47 / 255, alpha: 1)
    static let divider = NSColor(srgbRed: 0x23 / 255, green: 0x2E / 255, blue: 0x41 / 255, alpha: 1)
    static let lampYellow = NSColor(srgbRed: 0xF0 / 255, green: 0xB2 / 255, blue: 0x4E / 255, alpha: 1)
    static let lampYellowHover = NSColor(srgbRed: 0xFF / 255, green: 0xC4 / 255, blue: 0x64 / 255, alpha: 1)
    static let lampYellowPressed = NSColor(srgbRed: 0xD9 / 255, green: 0x9C / 255, blue: 0x3E / 255, alpha: 1)
    static let onLamp = NSColor(srgbRed: 0x3A / 255, green: 0x26 / 255, blue: 0x05 / 255, alpha: 1)
    static let badgeBackground = NSColor(srgbRed: 0x24 / 255, green: 0x1E / 255, blue: 0x12 / 255, alpha: 1)
    static let textPrimary = NSColor(srgbRed: 0xF2 / 255, green: 0xED / 255, blue: 0xE3 / 255, alpha: 1)
    static let textStep = NSColor(srgbRed: 0xD9 / 255, green: 0xDF / 255, blue: 0xE9 / 255, alpha: 1)
    static let textSecondary = NSColor(srgbRed: 0x93 / 255, green: 0xA0 / 255, blue: 0xB4 / 255, alpha: 1)
    static let textFaint = NSColor(srgbRed: 0x5C / 255, green: 0x68 / 255, blue: 0x78 / 255, alpha: 1)
    static let ghostHover = NSColor(srgbRed: 0x20 / 255, green: 0x2B / 255, blue: 0x3D / 255, alpha: 1)
    static let ghostPressed = NSColor(srgbRed: 0x18 / 255, green: 0x21 / 255, blue: 0x31 / 255, alpha: 1)
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

final class PrivatePinyinOnboardingWindowController: NSWindowController {
    static let shared = PrivatePinyinOnboardingWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PrivatePinyin Setup"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = StationTheme.windowBackground
        super.init(window: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showOnboarding() {
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

        let title = label(
            "输入法已经装好了。",
            font: .systemFont(ofSize: 24, weight: .semibold),
            color: StationTheme.textPrimary
        )
        let subtitle = wrappingLabel(
            "还差最后一步：把 PrivatePinyin 加进系统输入源，就可以在任何应用里打字了。",
            font: .systemFont(ofSize: 14, weight: .regular),
            color: StationTheme.textSecondary
        )

        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 8

        let stepCard = makeStepCard()
        let tip = makeTipRow()
        let footer = makeFooterRow()

        let brandRow = makeBrandRow()
        let root = NSStackView(views: [
            brandRow,
            heading,
            stepCard,
            tip,
            footer,
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 22
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),
            brandRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            subtitle.widthAnchor.constraint(equalTo: root.widthAnchor),
            stepCard.widthAnchor.constraint(equalTo: root.widthAnchor),
            tip.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func makeBrandRow() -> NSView {
        let mark = label(
            "拼",
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: StationTheme.onLamp
        )
        mark.alignment = .center

        let markBox = roundedBox(background: StationTheme.lampYellow, cornerRadius: 10)
        markBox.translatesAutoresizingMaskIntoConstraints = false
        mark.translatesAutoresizingMaskIntoConstraints = false
        markBox.addSubview(mark)

        NSLayoutConstraint.activate([
            markBox.widthAnchor.constraint(equalToConstant: 40),
            markBox.heightAnchor.constraint(equalToConstant: 40),
            mark.centerXAnchor.constraint(equalTo: markBox.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: markBox.centerYAnchor),
        ])

        let name = label(
            "PrivatePinyin",
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

        let row = NSStackView(views: [markBox, nameColumn, spacer, paddedBadge(text: "setup")])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeStepCard() -> NSView {
        let rows: [NSView] = [
            makeStepRow(number: 1, content: stepText("打开「键盘」设置"), isLast: false),
            makeStepRow(number: 2, content: stepText("在「文字输入 · 输入法」里点按「编辑」"), isLast: false),
            makeStepRow(number: 3, content: stepText("点 ＋，选择「简体中文」，添加「猫栈拼音」"), isLast: false),
            makeStepRow(number: 4, content: makeLastStepContent(), isLast: true),
        ]

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = roundedBox(background: StationTheme.cardBackground, cornerRadius: 12, border: StationTheme.border)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])
        return card
    }

    private func makeStepRow(number: Int, content: NSView, isLast: Bool) -> NSView {
        let chip = label(
            "\(number)",
            font: .systemFont(ofSize: 13, weight: .medium),
            color: StationTheme.lampYellow
        )
        chip.alignment = .center

        let chipBox = roundedBox(background: StationTheme.badgeBackground, cornerRadius: 7)
        chipBox.translatesAutoresizingMaskIntoConstraints = false
        chip.translatesAutoresizingMaskIntoConstraints = false
        chipBox.addSubview(chip)

        NSLayoutConstraint.activate([
            chipBox.widthAnchor.constraint(equalToConstant: 24),
            chipBox.heightAnchor.constraint(equalToConstant: 24),
            chip.centerXAnchor.constraint(equalTo: chipBox.centerXAnchor),
            chip.centerYAnchor.constraint(equalTo: chipBox.centerYAnchor),
        ])

        let row = NSStackView(views: [chipBox, content])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false

        guard !isLast else {
            return row
        }

        let container = NSStackView(views: [row, hairline()])
        container.orientation = .vertical
        container.alignment = .width
        container.spacing = 0

        return container
    }

    private func makeLastStepContent() -> NSView {
        let prefix = stepText("在任意应用里试打")
        let pinyin = inlineChip("nihao")
        let middle = stepText("空格上屏")
        let result = label(
            "你好",
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: StationTheme.lampYellow
        )

        let row = NSStackView(views: [prefix, pinyin, middle, result])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        return row
    }

    private func makeTipRow() -> NSView {
        let icon = label(
            "灯",
            font: .systemFont(ofSize: 12, weight: .medium),
            color: StationTheme.lampYellow
        )
        icon.alignment = .center

        let iconBox = roundedBox(background: StationTheme.badgeBackground, cornerRadius: 7, border: StationTheme.border)
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(icon)

        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 24),
            iconBox.heightAnchor.constraint(equalToConstant: 24),
            icon.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
        ])

        let text = wrappingLabel(
            "列表里没看到？清空搜索后选「中文（简体）」，或关掉系统设置再打开一次。",
            font: .systemFont(ofSize: 12, weight: .regular),
            color: StationTheme.textSecondary
        )

        let row = NSStackView(views: [iconBox, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeFooterRow() -> NSView {
        let openKeyboardButton = StationButton(
            title: "打开键盘设置",
            target: self,
            action: #selector(openKeyboardSettings(_:)),
            normalBackground: StationTheme.lampYellow,
            hoverBackground: StationTheme.lampYellowHover,
            pressedBackground: StationTheme.lampYellowPressed,
            titleColor: StationTheme.onLamp
        )
        openKeyboardButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true

        let closeButton = StationButton(
            title: "完成",
            target: self,
            action: #selector(closeWindow(_:)),
            normalBackground: .clear,
            hoverBackground: StationTheme.ghostHover,
            pressedBackground: StationTheme.ghostPressed,
            titleColor: StationTheme.textStep,
            borderColor: StationTheme.border
        )
        closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true

        let buttons = NSStackView(views: [openKeyboardButton, closeButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let signature = label(
            "a small station, still lit at night",
            font: .systemFont(ofSize: 11, weight: .regular),
            color: StationTheme.textFaint
        )
        signature.alignment = .right

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [buttons, spacer, signature])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func paddedBadge(text: String) -> NSView {
        let badgeLabel = label(
            text,
            font: .systemFont(ofSize: 11, weight: .regular),
            color: StationTheme.lampYellow
        )
        let box = roundedBox(background: StationTheme.badgeBackground, cornerRadius: 11, border: StationTheme.border)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            badgeLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
            badgeLabel.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
            badgeLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            badgeLabel.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
        ])
        return box
    }

    private func stepText(_ value: String) -> NSTextField {
        label(
            value,
            font: .systemFont(ofSize: 14, weight: .regular),
            color: StationTheme.textStep
        )
    }

    private func inlineChip(_ value: String) -> NSView {
        let text = label(
            value,
            font: .monospacedSystemFont(ofSize: 13, weight: .medium),
            color: StationTheme.textStep
        )
        let box = roundedBox(background: StationTheme.badgeBackground, cornerRadius: 7, border: StationTheme.divider)
        text.translatesAutoresizingMaskIntoConstraints = false
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(text)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: box.topAnchor, constant: 3),
            text.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -3),
            text.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
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
        text.setContentCompressionResistancePriority(.required, for: .vertical)
        return text
    }

    @objc private func openKeyboardSettings(_ sender: Any?) {
        let urls = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]

        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func closeWindow(_ sender: Any?) {
        window?.close()
    }
}
