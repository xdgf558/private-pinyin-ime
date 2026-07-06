import Cocoa

final class PrivatePinyinPreferencesWindowController: NSWindowController {
    static let shared = PrivatePinyinPreferencesWindowController()

    private let strictPrivacyButton = NSButton(
        checkboxWithTitle: "Strict Privacy Mode",
        target: nil,
        action: nil
    )
    private let predictionButton = NSButton(
        checkboxWithTitle: "Prediction Candidates",
        target: nil,
        action: nil
    )
    private let learningButton = NSButton(
        checkboxWithTitle: "User Learning",
        target: nil,
        action: nil
    )
    private let settingsPathLabel = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PrivatePinyin Preferences"
        window.isReleasedWhenClosed = false
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

        strictPrivacyButton.target = self
        strictPrivacyButton.action = #selector(settingChanged(_:))
        predictionButton.target = self
        predictionButton.action = #selector(settingChanged(_:))
        learningButton.target = self
        learningButton.action = #selector(settingChanged(_:))

        settingsPathLabel.lineBreakMode = .byTruncatingMiddle
        settingsPathLabel.textColor = .secondaryLabelColor

        let openSettingsButton = NSButton(
            title: "Open Settings File",
            target: self,
            action: #selector(openSettingsFile(_:))
        )
        let reloadButton = NSButton(
            title: "Reload",
            target: self,
            action: #selector(reloadButtonPressed(_:))
        )

        let controls = NSStackView(views: [
            strictPrivacyButton,
            predictionButton,
            learningButton,
        ])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 10

        let buttons = NSStackView(views: [openSettingsButton, reloadButton])
        buttons.orientation = .horizontal
        buttons.alignment = .leading
        buttons.spacing = 8

        let root = NSStackView(views: [
            NSTextField(labelWithString: "PrivatePinyin"),
            controls,
            settingsPathLabel,
            buttons,
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22),
            settingsPathLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func reloadFromSettings() {
        _ = PrivatePinyinSettingsStore.ensureSettingsFile()
        let settings = PrivatePinyinSettingsStore.settingsSnapshot()
        let strictPrivacy = settings["strict_privacy_mode"] as? Bool ?? false
        strictPrivacyButton.state = strictPrivacy ? .on : .off
        predictionButton.state = (settings["enable_prediction"] as? Bool ?? true) ? .on : .off
        learningButton.state = (settings["enable_user_learning"] as? Bool ?? true) ? .on : .off
        learningButton.isEnabled = !strictPrivacy
        settingsPathLabel.stringValue = PrivatePinyinSettingsStore.settingsURL.path
    }

    @objc private func settingChanged(_ sender: Any?) {
        let strictPrivacy = strictPrivacyButton.state == .on
        let ok = PrivatePinyinSettingsStore.updateSettings { settings in
            settings["strict_privacy_mode"] = strictPrivacy
            settings["enable_prediction"] = predictionButton.state == .on
            settings["enable_user_learning"] = strictPrivacy ? false : learningButton.state == .on
        }

        if ok {
            reloadFromSettings()
            NotificationCenter.default.post(name: .privatePinyinSettingsChanged, object: self)
        } else {
            showAlert("Could not update settings.")
        }
    }

    @objc private func openSettingsFile(_ sender: Any?) {
        guard PrivatePinyinSettingsStore.ensureSettingsFile() != nil else {
            showAlert("Could not create settings file.")
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
}

extension Notification.Name {
    static let privatePinyinSettingsChanged = Notification.Name("PrivatePinyinSettingsChanged")
}
