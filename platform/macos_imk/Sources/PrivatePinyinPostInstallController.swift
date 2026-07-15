import Cocoa

private enum ProcessRefreshTheme {
    static let windowBackground = NSColor(
        srgbRed: 0x13 / 255,
        green: 0x1A / 255,
        blue: 0x26 / 255,
        alpha: 1
    )
    static let cardBackground = NSColor(
        srgbRed: 0x1B / 255,
        green: 0x24 / 255,
        blue: 0x34 / 255,
        alpha: 1
    )
    static let border = NSColor(
        srgbRed: 0x2A / 255,
        green: 0x35 / 255,
        blue: 0x47 / 255,
        alpha: 1
    )
    static let lampYellow = NSColor(
        srgbRed: 0xF0 / 255,
        green: 0xB2 / 255,
        blue: 0x4E / 255,
        alpha: 1
    )
    static let lampYellowHover = NSColor(
        srgbRed: 0xFF / 255,
        green: 0xC4 / 255,
        blue: 0x64 / 255,
        alpha: 1
    )
    static let lampYellowPressed = NSColor(
        srgbRed: 0xD9 / 255,
        green: 0x9C / 255,
        blue: 0x3E / 255,
        alpha: 1
    )
    static let onLamp = NSColor(
        srgbRed: 0x3A / 255,
        green: 0x26 / 255,
        blue: 0x05 / 255,
        alpha: 1
    )
    static let textPrimary = NSColor(
        srgbRed: 0xF2 / 255,
        green: 0xED / 255,
        blue: 0xE3 / 255,
        alpha: 1
    )
    static let textSecondary = NSColor(
        srgbRed: 0x93 / 255,
        green: 0xA0 / 255,
        blue: 0xB4 / 255,
        alpha: 1
    )
    static let textFaint = NSColor(
        srgbRed: 0x5C / 255,
        green: 0x68 / 255,
        blue: 0x78 / 255,
        alpha: 1
    )
    static let ghostHover = NSColor(
        srgbRed: 0x20 / 255,
        green: 0x2B / 255,
        blue: 0x3D / 255,
        alpha: 1
    )
    static let ghostPressed = NSColor(
        srgbRed: 0x18 / 255,
        green: 0x21 / 255,
        blue: 0x31 / 255,
        alpha: 1
    )
}

private enum PrivatePinyinProcessRefreshResult {
    case refreshed
    case alreadyCurrent
    case stillRunning
}

private final class PrivatePinyinProcessRefreshService {
    private let bundleIdentifier = "com.privatepinyin.inputmethod.PrivatePinyin"
    private let currentProcessIdentifier = Int32(ProcessInfo.processInfo.processIdentifier)

    func staleProcessIdentifiers(installedAt: Date) -> Set<Int32> {
        PrivatePinyinProcessRefreshPolicy.staleProcessIdentifiers(
            in: currentSnapshots(),
            currentProcessIdentifier: currentProcessIdentifier,
            installedAt: installedAt
        )
    }

    func refresh(
        processIdentifiers: Set<Int32>,
        installedAt: Date,
        completion: @escaping (PrivatePinyinProcessRefreshResult) -> Void
    ) {
        let applications = matchingApplications()
        let eligibleIdentifiers = PrivatePinyinProcessRefreshPolicy.eligibleProcessIdentifiers(
            requestedProcessIdentifiers: processIdentifiers,
            currentSnapshots: snapshots(for: applications),
            currentProcessIdentifier: currentProcessIdentifier,
            installedAt: installedAt
        )

        guard !eligibleIdentifiers.isEmpty else {
            completion(.alreadyCurrent)
            return
        }

        for application in applications
        where eligibleIdentifiers.contains(Int32(application.processIdentifier)) {
            _ = application.terminate()
        }

        waitForExit(
            processIdentifiers: eligibleIdentifiers,
            deadline: Date().addingTimeInterval(4),
            completion: completion
        )
    }

    private func waitForExit(
        processIdentifiers: Set<Int32>,
        deadline: Date,
        completion: @escaping (PrivatePinyinProcessRefreshResult) -> Void
    ) {
        let runningIdentifiers = Set(
            matchingApplications().map { Int32($0.processIdentifier) }
        )
        guard !runningIdentifiers.isDisjoint(with: processIdentifiers) else {
            completion(.refreshed)
            return
        }

        guard Date() < deadline else {
            completion(.stillRunning)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForExit(
                processIdentifiers: processIdentifiers,
                deadline: deadline,
                completion: completion
            )
        }
    }

    private func currentSnapshots() -> [PrivatePinyinProcessSnapshot] {
        snapshots(for: matchingApplications())
    }

    private func snapshots(
        for applications: [NSRunningApplication]
    ) -> [PrivatePinyinProcessSnapshot] {
        applications.map { application in
            PrivatePinyinProcessSnapshot(
                processIdentifier: Int32(application.processIdentifier),
                launchDate: application.launchDate
            )
        }
    }

    private func matchingApplications() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }
}

final class PrivatePinyinPostInstallCoordinator {
    static let shared = PrivatePinyinPostInstallCoordinator()

    private let refreshService = PrivatePinyinProcessRefreshService()
    private var refreshWindowController: PrivatePinyinProcessRefreshWindowController?

    private init() {}

    func start(installedAt: Date?) {
        guard let installedAt else {
            PrivatePinyinOnboardingWindowController.shared.showOnboarding()
            return
        }

        let staleProcessIdentifiers = refreshService.staleProcessIdentifiers(installedAt: installedAt)
        guard !staleProcessIdentifiers.isEmpty else {
            PrivatePinyinOnboardingWindowController.shared.showOnboarding()
            return
        }

        let controller = PrivatePinyinProcessRefreshWindowController(
            processIdentifiers: staleProcessIdentifiers,
            installedAt: installedAt,
            refreshService: refreshService
        )
        refreshWindowController = controller
        controller.showRefreshGuidance()
    }
}

private final class ProcessRefreshButton: NSButton {
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
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
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

    func setTitle(_ value: String) {
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
                .font: font ?? NSFont.systemFont(ofSize: 14, weight: .medium),
            ]
        )
        alphaValue = isEnabled ? 1 : 0.62
    }
}

private final class PrivatePinyinProcessRefreshWindowController: NSWindowController {
    private let processIdentifiers: Set<Int32>
    private let installedAt: Date
    private let refreshService: PrivatePinyinProcessRefreshService

    private let titleLabel = NSTextField(labelWithString: "猫栈拼音已更新")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let statusTitleLabel = NSTextField(labelWithString: "")
    private let statusDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private lazy var refreshButton = ProcessRefreshButton(
        title: "重新加载猫栈拼音",
        target: self,
        action: #selector(refreshInputMethod(_:)),
        normalBackground: ProcessRefreshTheme.lampYellow,
        hoverBackground: ProcessRefreshTheme.lampYellowHover,
        pressedBackground: ProcessRefreshTheme.lampYellowPressed,
        titleColor: ProcessRefreshTheme.onLamp
    )
    private lazy var keyboardSettingsButton = ProcessRefreshButton(
        title: "打开键盘设置",
        target: self,
        action: #selector(openKeyboardSettings(_:)),
        normalBackground: .clear,
        hoverBackground: ProcessRefreshTheme.ghostHover,
        pressedBackground: ProcessRefreshTheme.ghostPressed,
        titleColor: ProcessRefreshTheme.textPrimary,
        borderColor: ProcessRefreshTheme.border
    )
    private lazy var closeButton = ProcessRefreshButton(
        title: "稍后",
        target: self,
        action: #selector(closeWindow(_:)),
        normalBackground: .clear,
        hoverBackground: ProcessRefreshTheme.ghostHover,
        pressedBackground: ProcessRefreshTheme.ghostPressed,
        titleColor: ProcessRefreshTheme.textPrimary,
        borderColor: ProcessRefreshTheme.border
    )

    init(
        processIdentifiers: Set<Int32>,
        installedAt: Date,
        refreshService: PrivatePinyinProcessRefreshService
    ) {
        self.processIdentifiers = processIdentifiers
        self.installedAt = installedAt
        self.refreshService = refreshService

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "猫栈拼音更新"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = ProcessRefreshTheme.windowBackground
        super.init(window: window)
        buildContent()
        showInitialState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showRefreshGuidance() {
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
        contentView.layer?.backgroundColor = ProcessRefreshTheme.windowBackground.cgColor

        let markLabel = makeLabel(
            "拼",
            font: .systemFont(ofSize: 18, weight: .bold),
            color: ProcessRefreshTheme.onLamp
        )
        markLabel.alignment = .center
        let mark = roundedBox(background: ProcessRefreshTheme.lampYellow, cornerRadius: 8)
        mark.translatesAutoresizingMaskIntoConstraints = false
        markLabel.translatesAutoresizingMaskIntoConstraints = false
        mark.addSubview(markLabel)

        let brandName = makeLabel(
            "猫栈拼音",
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: ProcessRefreshTheme.textPrimary
        )
        let brandDetail = makeLabel(
            "station cat · update relay",
            font: .monospacedSystemFont(ofSize: 10, weight: .regular),
            color: ProcessRefreshTheme.textSecondary
        )
        let brandText = NSStackView(views: [brandName, brandDetail])
        brandText.orientation = .vertical
        brandText.alignment = .leading
        brandText.spacing = 2

        let brandSpacer = NSView()
        brandSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let badge = makeBadge("UPDATE")
        let brandRow = NSStackView(views: [mark, brandText, brandSpacer, badge])
        brandRow.orientation = .horizontal
        brandRow.alignment = .centerY
        brandRow.spacing = 12

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = ProcessRefreshTheme.textPrimary
        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = ProcessRefreshTheme.textSecondary
        detailLabel.maximumNumberOfLines = 3
        let heading = NSStackView(views: [titleLabel, detailLabel])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 8

        statusTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusTitleLabel.textColor = ProcessRefreshTheme.textPrimary
        statusDetailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        statusDetailLabel.textColor = ProcessRefreshTheme.textSecondary
        statusDetailLabel.maximumNumberOfLines = 3
        let statusText = NSStackView(views: [statusTitleLabel, statusDetailLabel])
        statusText.orientation = .vertical
        statusText.alignment = .leading
        statusText.spacing = 5

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        let statusSpacer = NSView()
        statusSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let statusRow = NSStackView(views: [statusText, statusSpacer, progressIndicator])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 16
        statusRow.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        statusRow.wantsLayer = true
        statusRow.layer?.backgroundColor = ProcessRefreshTheme.cardBackground.cgColor
        statusRow.layer?.cornerRadius = 8
        statusRow.layer?.borderWidth = 1
        statusRow.layer?.borderColor = ProcessRefreshTheme.border.cgColor

        refreshButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 154).isActive = true
        keyboardSettingsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 128).isActive = true
        closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [refreshButton, keyboardSettingsButton, buttonSpacer, closeButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let footer = makeLabel(
            "只处理猫栈拼音自己的旧进程",
            font: .monospacedSystemFont(ofSize: 10, weight: .regular),
            color: ProcessRefreshTheme.textFaint
        )

        let root = NSStackView(views: [brandRow, heading, statusRow, buttonRow, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 40),
            mark.heightAnchor.constraint(equalToConstant: 40),
            markLabel.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            markLabel.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            brandRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusDetailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 410),
            buttonRow.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func showInitialState() {
        titleLabel.stringValue = "猫栈拼音已更新"
        detailLabel.stringValue = "macOS 还在运行安装前启动的猫栈拼音。请先完成当前正在输入的内容，再重新加载新版。"
        statusTitleLabel.stringValue = "发现旧版输入进程"
        statusDetailLabel.stringValue = "刷新只会请求退出猫栈拼音自己的旧进程，不会关闭浏览器、编辑器或其他应用。"
        progressIndicator.stopAnimation(nil)
        refreshButton.isHidden = false
        refreshButton.isEnabled = true
        refreshButton.setTitle("重新加载猫栈拼音")
        keyboardSettingsButton.isHidden = true
        closeButton.setTitle("稍后")
    }

    private func showRefreshingState() {
        statusTitleLabel.stringValue = "正在重新加载"
        statusDetailLabel.stringValue = "请稍候，当前应用和已保存的文稿不会被关闭。"
        progressIndicator.startAnimation(nil)
        refreshButton.isEnabled = false
        refreshButton.setTitle("正在重新加载…")
    }

    private func showSuccessState() {
        titleLabel.stringValue = "新版已经接上"
        detailLabel.stringValue = "切到其他输入法，再切回「猫栈拼音」即可继续使用。"
        statusTitleLabel.stringValue = "重新加载完成"
        statusDetailLabel.stringValue = "无需注销，也无需重启电脑。若当前应用尚未刷新，重新聚焦输入框即可。"
        progressIndicator.stopAnimation(nil)
        refreshButton.isHidden = true
        keyboardSettingsButton.isHidden = false
        closeButton.setTitle("完成")
    }

    private func showLogoutGuidance() {
        titleLabel.stringValue = "还差一次系统会话刷新"
        detailLabel.stringValue = "macOS 暂时没有退出旧输入法进程。请先保存其他应用中的工作。"
        statusTitleLabel.stringValue = "请注销并重新登录"
        statusDetailLabel.stringValue = "从 Apple 菜单选择「注销」，重新登录后就是新版；无需先重启电脑。"
        progressIndicator.stopAnimation(nil)
        refreshButton.isHidden = true
        keyboardSettingsButton.isHidden = true
        closeButton.setTitle("知道了")
    }

    @objc private func refreshInputMethod(_ sender: Any?) {
        showRefreshingState()
        refreshService.refresh(
            processIdentifiers: processIdentifiers,
            installedAt: installedAt
        ) { [weak self] result in
            switch result {
            case .refreshed, .alreadyCurrent:
                self?.showSuccessState()
            case .stillRunning:
                self?.showLogoutGuidance()
            }
        }
    }

    @objc private func openKeyboardSettings(_ sender: Any?) {
        let values = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]
        for value in values {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func closeWindow(_ sender: Any?) {
        window?.close()
    }

    private func makeBadge(_ value: String) -> NSView {
        let badgeLabel = makeLabel(
            value,
            font: .monospacedSystemFont(ofSize: 10, weight: .semibold),
            color: ProcessRefreshTheme.lampYellow
        )
        let box = roundedBox(background: .clear, cornerRadius: 8, border: ProcessRefreshTheme.lampYellow)
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

    private func roundedBox(
        background: NSColor,
        cornerRadius: CGFloat,
        border: NSColor? = nil
    ) -> NSView {
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

    private func makeLabel(_ value: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = font
        label.textColor = color
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
}
