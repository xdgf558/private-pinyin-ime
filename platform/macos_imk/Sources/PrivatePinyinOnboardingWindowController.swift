import Cocoa

final class PrivatePinyinOnboardingWindowController: NSWindowController {
    static let shared = PrivatePinyinOnboardingWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PrivatePinyin Setup"
        window.isReleasedWhenClosed = false
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

        let title = NSTextField(labelWithString: "PrivatePinyin is installed")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let summary = NSTextField(wrappingLabelWithString: "Add PrivatePinyin in macOS Keyboard settings, then switch to it from the menu bar input menu or with Control-Space.")
        summary.textColor = .secondaryLabelColor

        let steps = NSTextField(wrappingLabelWithString: """
        1. Open Keyboard Settings.
        2. Under Text Input, click Edit next to Input Sources.
        3. Click +, choose Chinese, then select PrivatePinyin.
        4. Open TextEdit, switch to PrivatePinyin, type nihao, and press Space.
        """)
        steps.lineBreakMode = .byWordWrapping

        let note = NSTextField(wrappingLabelWithString: "If PrivatePinyin does not appear immediately, close System Settings and open it again. A logout/login refresh may be required for unsigned local test builds.")
        note.textColor = .secondaryLabelColor

        let openKeyboardButton = NSButton(
            title: "Open Keyboard Settings",
            target: self,
            action: #selector(openKeyboardSettings(_:))
        )
        openKeyboardButton.bezelStyle = .rounded

        let closeButton = NSButton(
            title: "Done",
            target: self,
            action: #selector(closeWindow(_:))
        )
        closeButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [openKeyboardButton, closeButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let root = NSStackView(views: [
            title,
            summary,
            steps,
            note,
            buttons,
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -26),
            summary.widthAnchor.constraint(equalTo: root.widthAnchor),
            steps.widthAnchor.constraint(equalTo: root.widthAnchor),
            note.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
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
