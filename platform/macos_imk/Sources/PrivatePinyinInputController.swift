import Cocoa
import InputMethodKit

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
        candidatePanel = IMKCandidates(
            server: server,
            panelType: kIMKSingleColumnScrollingCandidatePanel
        )
        candidatePanel?.setDismissesAutomatically(true)
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
}
