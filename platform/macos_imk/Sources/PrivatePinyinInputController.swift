import Cocoa
import InputMethodKit
import UniformTypeIdentifiers

private enum PrivatePinyinCandidatePanelStore {
    private static let selectionKeyCodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        .map(NSNumber.init(value:))
    private static var panel: IMKCandidates?

    static func sharedPanel(for server: IMKServer!) -> IMKCandidates? {
        if let panel {
            return panel
        }
        guard let server else {
            return nil
        }

        let panel = IMKCandidates(
            server: server,
            panelType: kIMKSingleRowSteppingCandidatePanel
        )
        panel?.setSelectionKeys(selectionKeyCodes)
        panel?.setAttributes([IMKCandidatesSendServerKeyEventFirst: true])
        panel?.setDismissesAutomatically(true)
        self.panel = panel
        return panel
    }
}

@objc(PrivatePinyinInputController)
final class PrivatePinyinInputController: IMKInputController {
    private let core = PinyinCoreBridge()
    private var candidatePanel: IMKCandidates?
    private var currentPreedit = ""
    private var currentCandidates: [PinyinCandidate] = []
    private var hasActiveInput = false
    private var pendingShiftToggle = false

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        candidatePanel = PrivatePinyinCandidatePanelStore.sharedPanel(for: server)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged(_:)),
            name: .privatePinyinSettingsChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc(handleEvent:client:)
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else {
            return false
        }

        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event, client: sender)
        default:
            return false
        }
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    @objc(composedString:)
    override func composedString(_ sender: Any!) -> Any! {
        currentPreedit
    }

    @objc(candidates:)
    override func candidates(_ sender: Any!) -> [Any]! {
        currentCandidates.map(\.text)
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "猫栈")

        let preferencesItem = NSMenuItem(
            title: "偏好设置...",
            action: #selector(openPreferences(_:)),
            keyEquivalent: ""
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let updateItem = NSMenuItem(
            title: PrivatePinyinUpdateController.shared.menuTitle,
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.isEnabled = PrivatePinyinUpdateController.shared.isMenuActionEnabled
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let privacyItem = NSMenuItem(
            title: "严格隐私模式",
            action: #selector(toggleStrictPrivacyMode(_:)),
            keyEquivalent: ""
        )
        privacyItem.target = self
        privacyItem.state = PrivatePinyinSettingsStore.isStrictPrivacyModeEnabled() ? .on : .off
        menu.addItem(privacyItem)

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(
            title: "清空用户词库",
            action: #selector(clearUserLexicon(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        let exportItem = NSMenuItem(
            title: "导出用户词库...",
            action: #selector(exportUserLexicon(_:)),
            keyEquivalent: ""
        )
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(NSMenuItem.separator())

        let importItem = NSMenuItem(
            title: "导入 Rime 词库...",
            action: #selector(importRimeLexicon(_:)),
            keyEquivalent: ""
        )
        importItem.target = self
        menu.addItem(importItem)

        let clearImportedItem = NSMenuItem(
            title: "清空导入词库",
            action: #selector(clearImportedLexicon(_:)),
            keyEquivalent: ""
        )
        clearImportedItem.target = self
        menu.addItem(clearImportedItem)

        menu.addItem(NSMenuItem.separator())

        let openSettingsItem = NSMenuItem(
            title: "打开设置文件",
            action: #selector(openSettingsFile(_:)),
            keyEquivalent: ""
        )
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)

        return menu
    }

    @objc(candidateSelected:)
    override func candidateSelected(_ candidateString: NSAttributedString!) {
        let selected = candidateString?.string ?? ""
        guard let index = currentCandidates.firstIndex(where: { $0.text == selected }),
              let output = core?.commitCandidate(index: index) else {
            commitText(selected)
            resetComposition()
            return
        }
        apply(output)
    }

    override func commitComposition(_ sender: Any!) {
        if hasActiveInput,
           let output = core?.feed(
               MappedKey(
                   keyCode: ImeKeyCodeValue.enter,
                   text: "\n",
                   shift: false,
                   ctrl: false,
                   alt: false,
                   meta: false,
                   isRepeat: false,
                   timestampMs: Int64(Date().timeIntervalSince1970 * 1000.0)
               )
           ) {
            apply(output)
        } else {
            resetComposition()
        }
    }

    override func activateServer(_ sender: Any!) {
        pendingShiftToggle = false
    }

    override func deactivateServer(_ sender: Any!) {
        resetComposition()
    }

    override func inputControllerWillClose() {
        resetComposition()
    }

    override func hidePalettes() {
        candidatePanel?.hide()
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        guard MacKeyMapper.isShiftKey(event), !MacKeyMapper.hasSystemModifier(event) else {
            pendingShiftToggle = false
            return false
        }

        if MacKeyMapper.isShiftDown(event) {
            pendingShiftToggle = true
            return false
        }

        if pendingShiftToggle {
            pendingShiftToggle = false
            guard let output = core?.feed(MacKeyMapper.shiftToggleEvent(timestamp: event.timestamp)) else {
                return false
            }
            apply(output)
            return true
        }

        return false
    }

    private func handleKeyDown(_ event: NSEvent, client sender: Any!) -> Bool {
        if MacKeyMapper.isShiftDown(event) {
            pendingShiftToggle = false
        }

        guard let mappedKey = MacKeyMapper.mapKeyDown(event), shouldHandle(mappedKey) else {
            return false
        }

        guard let output = core?.feed(mappedKey) else {
            return false
        }
        apply(output)
        return true
    }

    private func shouldHandle(_ key: MappedKey) -> Bool {
        if key.ctrl || key.alt || key.meta {
            return false
        }

        switch key.keyCode {
        case ImeKeyCodeValue.enter,
             ImeKeyCodeValue.backspace,
             ImeKeyCodeValue.escape,
             ImeKeyCodeValue.pageUp,
             ImeKeyCodeValue.pageDown,
             ImeKeyCodeValue.arrowUp,
             ImeKeyCodeValue.arrowDown,
             ImeKeyCodeValue.digit:
            return hasActiveInput
        default:
            return true
        }
    }

    private func apply(_ output: PinyinOutput) {
        currentPreedit = output.preedit
        currentCandidates = output.candidates

        if output.shouldCommit, !output.commitText.isEmpty {
            commitText(output.commitText)
        }

        if output.shouldUpdatePreedit {
            if output.preedit.isEmpty {
                clearMarkedText()
            } else {
                updateComposition()
            }
        }

        updateCandidatePanel(visible: output.shouldShowCandidates && !output.candidates.isEmpty)
        hasActiveInput = !currentPreedit.isEmpty || !currentCandidates.isEmpty
    }

    private func updateCandidatePanel(visible: Bool) {
        guard let candidatePanel else {
            return
        }

        if visible {
            candidatePanel.setCandidateData(currentCandidates.map(\.text))
            candidatePanel.update()
            candidatePanel.show(kIMKLocateCandidatesBelowHint)
        } else {
            candidatePanel.hide()
        }
    }

    private func commitText(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        client()?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func clearMarkedText() {
        client()?.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func resetComposition() {
        _ = core?.resetSession()
        currentPreedit = ""
        currentCandidates = []
        hasActiveInput = false
        pendingShiftToggle = false
        candidatePanel?.hide()
        clearMarkedText()
    }

    @objc private func toggleStrictPrivacyMode(_ sender: Any?) {
        let enabled = !PrivatePinyinSettingsStore.isStrictPrivacyModeEnabled()
        guard PrivatePinyinSettingsStore.setStrictPrivacyMode(enabled) else {
            showSettingsAlert("无法更新设置。")
            return
        }
        PrivatePinyinUpdateController.shared.applyCurrentPrivacyPolicy()
        resetComposition()
        guard core?.reload() == true else {
            showSettingsAlert("无法重新加载猫栈拼音。")
            return
        }
        showSettingsAlert(enabled ? "严格隐私模式已开启。" : "严格隐私模式已关闭。")
    }

    @objc private func openPreferences(_ sender: Any?) {
        PrivatePinyinPreferencesWindowController.shared.showPreferences()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        PrivatePinyinUpdateController.shared.checkOrPresentUpdate()
    }

    @objc private func settingsChanged(_ notification: Notification) {
        resetComposition()
        _ = core?.reload()
    }

    @objc private func clearUserLexicon(_ sender: Any?) {
        resetComposition()
        if core?.clearUserLexicon() == true {
            showSettingsAlert("用户词库已清空。")
        } else {
            showSettingsAlert("无法清空用户词库。")
        }
    }

    @objc private func exportUserLexicon(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "private-pinyin-user-lexicon.tsv"
        panel.begin { [weak self] response in
            guard
                response == .OK,
                let url = panel.url,
                let self
            else {
                return
            }

            if self.core?.exportUserLexicon(to: url.path) == true {
                self.showSettingsAlert("用户词库已导出。")
            } else {
                self.showSettingsAlert("无法导出用户词库。")
            }
        }
    }

    @objc private func importRimeLexicon(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["yaml", "yml", "dict"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.message = "选择带有明确拼音列的 Rime YAML 词典。导入数据只保存在本机。"
        panel.begin { [weak self] response in
            guard response == .OK, let self else {
                return
            }

            var accepted = 0
            for url in panel.urls {
                guard let count = self.core?.importRimeLexicon(from: url.path) else {
                    if accepted > 0 {
                        resetComposition()
                        _ = core?.reload()
                        self.showSettingsAlert(
                            "已导入 \(accepted) 条记录，但后续文件导入失败。请检查剩余文件的格式和大小。"
                        )
                    } else {
                        self.showSettingsAlert("无法导入 Rime 词库。请确认文件格式和大小。")
                    }
                    return
                }
                accepted += count
            }

            resetComposition()
            _ = core?.reload()
            showSettingsAlert("已导入 \(accepted) 条词库记录。")
        }
    }

    @objc private func clearImportedLexicon(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "清空导入词库？"
        alert.informativeText = "只会删除手动导入的词库，不影响内置词库和用户学习数据。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        resetComposition()
        if core?.clearImportedLexicon() == true, core?.reload() == true {
            showSettingsAlert("导入词库已清空。")
        } else {
            showSettingsAlert("无法清空导入词库。")
        }
    }

    @objc private func openSettingsFile(_ sender: Any?) {
        guard PrivatePinyinSettingsStore.ensureSettingsFile() != nil else {
            showSettingsAlert("无法创建设置文件。")
            return
        }
        NSWorkspace.shared.open(PrivatePinyinSettingsStore.settingsURL)
    }

    private func showSettingsAlert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
