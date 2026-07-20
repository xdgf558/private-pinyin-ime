import Foundation

@main
enum SharedEnginePoolTests {
    static func main() {
        let bridges = (0..<24).compactMap { _ in
            PinyinCoreBridge(settingsPathForTesting: nil)
        }
        require(bridges.count == 24, "all client sessions are created")
        require(
            PinyinCoreBridge.sharedEngineLoadCountForTesting == 1,
            "multiple macOS client controllers share one parsed engine"
        )

        let leftOutput = bridges[0].feed(character("n"))
        let rightOutput = bridges[1].feed(character("h"))
        require(leftOutput?.preedit == "n", "the first client keeps its own composition")
        require(rightOutput?.preedit == "h", "the second client keeps its own composition")

        for bridge in bridges {
            require(bridge.reload(), "session reload succeeds")
        }
        require(
            PinyinCoreBridge.sharedEngineLoadCountForTesting == 1,
            "an unchanged configuration does not reparse the lexicon during reload fan-out"
        )

        print("macOS shared engine pool tests passed.")
    }

    private static func character(_ text: String) -> MappedKey {
        MappedKey(
            keyCode: ImeKeyCodeValue.character,
            text: text,
            shift: false,
            ctrl: false,
            alt: false,
            meta: false,
            isRepeat: false,
            timestampMs: 0
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
