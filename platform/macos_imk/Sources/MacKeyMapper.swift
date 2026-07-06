import Carbon
import Cocoa

enum ImeKeyCodeValue {
    static let unknown: Int32 = 0
    static let space: Int32 = 1
    static let enter: Int32 = 2
    static let backspace: Int32 = 3
    static let escape: Int32 = 4
    static let shift: Int32 = 5
    static let comma: Int32 = 8
    static let period: Int32 = 9
    static let minus: Int32 = 10
    static let equal: Int32 = 11
    static let apostrophe: Int32 = 12
    static let semicolon: Int32 = 13
    static let pageUp: Int32 = 14
    static let pageDown: Int32 = 15
    static let arrowUp: Int32 = 16
    static let arrowDown: Int32 = 17
    static let character: Int32 = 100
    static let digit: Int32 = 101
}

struct MappedKey {
    let keyCode: Int32
    let text: String
    let shift: Bool
    let ctrl: Bool
    let alt: Bool
    let meta: Bool
    let isRepeat: Bool
    let timestampMs: Int64
}

enum MacKeyMapper {
    static func mapKeyDown(_ event: NSEvent) -> MappedKey? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = flags.contains(.shift)
        let ctrl = flags.contains(.control)
        let alt = flags.contains(.option)
        let meta = flags.contains(.command)

        if ctrl || alt || meta {
            return nil
        }

        let timestampMs = Int64(event.timestamp * 1000.0)
        let base = KeyBase(
            shift: shift,
            ctrl: ctrl,
            alt: alt,
            meta: meta,
            isRepeat: event.isARepeat,
            timestampMs: timestampMs
        )

        switch Int(event.keyCode) {
        case kVK_Space:
            return base.make(code: ImeKeyCodeValue.space, text: " ")
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return base.make(code: ImeKeyCodeValue.enter, text: "\n")
        case kVK_Delete:
            return base.make(code: ImeKeyCodeValue.backspace)
        case kVK_Escape:
            return base.make(code: ImeKeyCodeValue.escape)
        case kVK_UpArrow:
            return base.make(code: ImeKeyCodeValue.arrowUp)
        case kVK_DownArrow:
            return base.make(code: ImeKeyCodeValue.arrowDown)
        case kVK_PageUp:
            return base.make(code: ImeKeyCodeValue.pageUp)
        case kVK_PageDown:
            return base.make(code: ImeKeyCodeValue.pageDown)
        case kVK_ANSI_Comma:
            return shift ? nil : base.make(code: ImeKeyCodeValue.comma, text: ",")
        case kVK_ANSI_Period:
            return shift ? nil : base.make(code: ImeKeyCodeValue.period, text: ".")
        case kVK_ANSI_Minus:
            return shift ? nil : base.make(code: ImeKeyCodeValue.minus, text: "-")
        case kVK_ANSI_Equal:
            return shift ? nil : base.make(code: ImeKeyCodeValue.equal, text: "=")
        case kVK_ANSI_Quote:
            return shift ? nil : base.make(code: ImeKeyCodeValue.apostrophe, text: "'")
        case kVK_ANSI_Semicolon:
            return shift ? nil : base.make(code: ImeKeyCodeValue.semicolon, text: ";")
        default:
            return mapPrintable(event, base: base)
        }
    }

    static func shiftToggleEvent(timestamp: TimeInterval) -> MappedKey {
        MappedKey(
            keyCode: ImeKeyCodeValue.shift,
            text: "",
            shift: false,
            ctrl: false,
            alt: false,
            meta: false,
            isRepeat: false,
            timestampMs: Int64(timestamp * 1000.0)
        )
    }

    static func isShiftKey(_ event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        return keyCode == kVK_Shift || keyCode == kVK_RightShift
    }

    static func isShiftDown(_ event: NSEvent) -> Bool {
        event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift)
    }

    static func hasSystemModifier(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.control) || flags.contains(.option) || flags.contains(.command)
    }

    private static func mapPrintable(_ event: NSEvent, base: KeyBase) -> MappedKey? {
        guard let character = event.charactersIgnoringModifiers?.first else {
            return nil
        }

        if character.isASCII && character.isLetter {
            guard !base.shift else {
                return nil
            }
            return base.make(
                code: ImeKeyCodeValue.character,
                text: String(character).lowercased()
            )
        }

        if character.isASCII && character.isNumber {
            guard !base.shift else {
                return nil
            }
            return base.make(code: ImeKeyCodeValue.digit, text: String(character))
        }

        return nil
    }
}

private struct KeyBase {
    let shift: Bool
    let ctrl: Bool
    let alt: Bool
    let meta: Bool
    let isRepeat: Bool
    let timestampMs: Int64

    func make(code: Int32, text: String = "") -> MappedKey {
        MappedKey(
            keyCode: code,
            text: text,
            shift: shift,
            ctrl: ctrl,
            alt: alt,
            meta: meta,
            isRepeat: isRepeat,
            timestampMs: timestampMs
        )
    }
}
