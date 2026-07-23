import Cocoa

final class PrivatePinyinWriterWindowController: NSWindowController {
    static let shared = PrivatePinyinWriterWindowController()

    private let sourceView = NSTextView(frame: .zero)
    private let featurePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let enabledButton = NSButton(checkboxWithTitle: "启用本地 Writer", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let resultsStack = NSStackView()
    private let runButton = NSButton(title: "生成建议", target: nil, action: nil)

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 590),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "猫栈 Writer"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(
            srgbRed: 0x14 / 255,
            green: 0x1B / 255,
            blue: 0x2D / 255,
            alpha: 1
        )
        super.init(window: window)
        buildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelStateChanged(_:)),
            name: .privatePinyinWriterModelStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged(_:)),
            name: .privatePinyinSettingsChanged,
            object: nil
        )
        reloadState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showWriter() {
        reloadState()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let accent = NSColor(srgbRed: 0xF0 / 255, green: 0xB2 / 255, blue: 0x4E / 255, alpha: 1)
        let primary = NSColor(srgbRed: 0xF2 / 255, green: 0xED / 255, blue: 0xE3 / 255, alpha: 1)
        let secondary = NSColor(srgbRed: 0x93 / 255, green: 0xA0 / 255, blue: 0xB4 / 255, alpha: 1)

        let title = NSTextField(labelWithString: "本地 Writer")
        title.font = .systemFont(ofSize: 25, weight: .bold)
        title.textColor = primary
        let detail = NSTextField(wrappingLabelWithString: "改写与翻译只在本机处理。源文本通过已认证 Helper 发送，不进入命令行、日志或临时文件。")
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = secondary

        featurePicker.addItems(withTitles: PrivatePinyinWriterFeature.allCases.map(\.title))
        featurePicker.font = .systemFont(ofSize: 14, weight: .medium)
        enabledButton.target = self
        enabledButton.action = #selector(writerEnabledChanged(_:))
        enabledButton.contentTintColor = accent

        let sourceLabel = NSTextField(labelWithString: "原文")
        sourceLabel.textColor = primary
        sourceLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        sourceView.font = .systemFont(ofSize: 15)
        sourceView.textColor = primary
        sourceView.backgroundColor = NSColor(srgbRed: 0x21 / 255, green: 0x2B / 255, blue: 0x42 / 255, alpha: 1)
        sourceView.textContainerInset = NSSize(width: 12, height: 10)
        let sourceScroll = NSScrollView()
        sourceScroll.documentView = sourceView
        sourceScroll.hasVerticalScroller = true
        sourceScroll.drawsBackground = false
        sourceScroll.translatesAutoresizingMaskIntoConstraints = false
        sourceScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        runButton.target = self
        runButton.action = #selector(runWriter(_:))
        runButton.bezelStyle = .rounded
        runButton.contentTintColor = accent
        statusLabel.textColor = secondary
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        let resultLabel = NSTextField(labelWithString: "建议")
        resultLabel.textColor = primary
        resultLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 8

        let topControls = NSStackView(views: [featurePicker, enabledButton, NSView(), runButton])
        topControls.orientation = .horizontal
        topControls.alignment = .centerY
        topControls.spacing = 12
        topControls.arrangedSubviews[2].setContentHuggingPriority(.defaultLow, for: .horizontal)

        let root = NSStackView(views: [title, detail, topControls, sourceLabel, sourceScroll, statusLabel, resultLabel, resultsStack])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            detail.widthAnchor.constraint(equalTo: root.widthAnchor),
            topControls.widthAnchor.constraint(equalTo: root.widthAnchor),
            sourceScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            resultsStack.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func reloadState() {
        let settings = PrivatePinyinSettingsStore.settingsSnapshot()
        enabledButton.state = PrivatePinyinSettingsStore.isWriterActionsEnabled(settings: settings)
            ? .on
            : .off
        let strict = settings["strict_privacy_mode"] as? Bool ?? false
        enabledButton.isEnabled = !strict
        let installed = PrivatePinyinWriterModelManager.shared.isInstalled
        runButton.isEnabled = installed && !strict && enabledButton.state == .on
        if strict {
            statusLabel.stringValue = "严格隐私模式已关闭 Writer。"
        } else if !installed {
            statusLabel.stringValue = "尚未安装 Writer 模型，请先在偏好设置中下载。"
        } else if enabledButton.state != .on {
            statusLabel.stringValue = "Writer 默认关闭。确认启用后才会处理你主动提交的原文。"
        } else {
            statusLabel.stringValue = "模型已就绪。普通拼音输入不依赖 Writer。"
        }
    }

    @objc private func modelStateChanged(_ notification: Notification) {
        reloadState()
    }

    @objc private func settingsChanged(_ notification: Notification) {
        reloadState()
    }

    @objc private func writerEnabledChanged(_ sender: NSButton) {
        guard PrivatePinyinSettingsStore.setWriterActionsEnabled(sender.state == .on) else {
            sender.state = .off
            showAlert("无法保存 Writer 设置。")
            return
        }
        reloadState()
        NotificationCenter.default.post(name: .privatePinyinSettingsChanged, object: self)
    }

    @objc private func runWriter(_ sender: Any?) {
        guard writerRunIsAllowed() else {
            reloadState()
            showAlert("请先安装模型、关闭严格隐私模式，并明确启用本地 Writer。")
            return
        }
        let source = sourceView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            showAlert("请先输入需要处理的文字。")
            return
        }
        guard source.utf8.count <= 4_096, source.count <= 600 else {
            showAlert("原文过长，请控制在 600 个字符以内。")
            return
        }
        guard let feature = PrivatePinyinWriterFeature.allCases[safe: featurePicker.indexOfSelectedItem] else {
            return
        }
        runButton.isEnabled = false
        statusLabel.stringValue = "正在本机生成建议..."
        clearResults()
        PrivatePinyinAIHelperClient.shared.prepareWriter { [weak self] prepareResult in
            DispatchQueue.main.async {
                guard let self else { return }
                switch prepareResult {
                case .failure:
                    self.reloadState()
                    self.statusLabel.stringValue = "模型启动失败。普通输入不受影响。"
                case .success:
                    guard self.writerRunIsAllowed() else {
                        self.reloadState()
                        self.statusLabel.stringValue = "设置已变化，本次 Writer 请求已取消。"
                        return
                    }
                    PrivatePinyinAIHelperClient.shared.submitWriter(
                        feature: feature,
                        source: source
                    ) { [weak self] result in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            guard self.writerRunIsAllowed() else {
                                self.clearResults()
                                self.reloadState()
                                self.statusLabel.stringValue = "设置已变化，生成结果已丢弃。"
                                return
                            }
                            self.runButton.isEnabled = true
                            switch result {
                            case let .success(suggestions):
                                self.statusLabel.stringValue = "已生成 \(suggestions.count) 条建议；点击即可复制。"
                                self.showResults(suggestions)
                            case .failure:
                                self.statusLabel.stringValue = "生成失败或超时。原文未被修改。"
                            }
                        }
                    }
                }
            }
        }
    }

    private func writerRunIsAllowed() -> Bool {
        PrivatePinyinWriterModelManager.shared.isInstalled
            && PrivatePinyinSettingsStore.isWriterActionsEnabled()
    }

    private func showResults(_ suggestions: [String]) {
        clearResults()
        for suggestion in suggestions {
            let button = NSButton(title: suggestion, target: self, action: #selector(copySuggestion(_:)))
            button.bezelStyle = .recessed
            button.alignment = .left
            button.lineBreakMode = .byWordWrapping
            button.toolTip = "复制这条建议"
            button.identifier = NSUserInterfaceItemIdentifier(suggestion)
            button.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            resultsStack.addArrangedSubview(button)
        }
    }

    private func clearResults() {
        resultsStack.arrangedSubviews.forEach {
            resultsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    @objc private func copySuggestion(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusLabel.stringValue = "建议已复制。"
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
