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

        verifyReviewedLexiconLayersInvalidateSharedSnapshot()

        print("macOS shared engine pool tests passed.")
    }

    private static func verifyReviewedLexiconLayersInvalidateSharedSnapshot() {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "PrivatePinyin-SharedEngine-\(UUID().uuidString)",
            isDirectory: true
        )
        try! fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let settingsURL = temporaryDirectory.appendingPathComponent("settings.json")
        let rimeIceURL = temporaryDirectory.appendingPathComponent("rime_ice.tsv")
        let rimeFrostURL = temporaryDirectory.appendingPathComponent("rime_frost.tsv")
        let settings: [String: Any] = [
            "rime_ice_lexicon_path": rimeIceURL.path,
            "enable_rime_ice_lexicon": true,
            "rime_frost_lexicon_path": rimeFrostURL.path,
            "enable_rime_frost_lexicon": true,
        ]
        let settingsData = try! JSONSerialization.data(
            withJSONObject: settings,
            options: [.sortedKeys]
        )
        try! settingsData.write(to: settingsURL, options: .atomic)

        let bridge = PinyinCoreBridge(settingsPathForTesting: settingsURL.path)
        require(bridge != nil, "a configured shared-engine session is created")
        let configuredLoadCount = PinyinCoreBridge.sharedEngineLoadCountForTesting

        try! Data("白霜测试\tbai shuang ce shi\t9000\n".utf8)
            .write(to: rimeFrostURL, options: .atomic)
        require(bridge?.reload() == true, "a new White Frost layer reloads the session")
        require(
            PinyinCoreBridge.sharedEngineLoadCountForTesting == configuredLoadCount + 1,
            "a new White Frost file invalidates the shared-engine fingerprint"
        )
        require(
            candidateTexts(for: "baishuangceshi", using: bridge).contains("白霜测试"),
            "the reloaded engine exposes a White Frost-only candidate"
        )
        _ = bridge?.resetSession()

        try! Data("雾凇测试\twu song ce shi\t8000\n".utf8)
            .write(to: rimeIceURL, options: .atomic)
        require(bridge?.reload() == true, "a new Rime Ice layer reloads the session")
        require(
            PinyinCoreBridge.sharedEngineLoadCountForTesting == configuredLoadCount + 2,
            "a new Rime Ice file invalidates the shared-engine fingerprint"
        )
        require(
            candidateTexts(for: "wusongceshi", using: bridge).contains("雾凇测试"),
            "the reloaded engine exposes a Rime Ice-only candidate"
        )
        _ = bridge?.resetSession()

        try! fileManager.removeItem(at: rimeFrostURL)
        require(bridge?.reload() == true, "removing White Frost reloads the session")
        require(
            PinyinCoreBridge.sharedEngineLoadCountForTesting == configuredLoadCount + 3,
            "removing White Frost invalidates the shared-engine fingerprint"
        )
        require(
            !candidateTexts(for: "baishuangceshi", using: bridge).contains("白霜测试"),
            "the reloaded engine drops candidates from a cleared White Frost layer"
        )
        _ = bridge?.resetSession()
    }

    private static func candidateTexts(
        for input: String,
        using bridge: PinyinCoreBridge?
    ) -> [String] {
        var output: PinyinOutput?
        for character in input {
            output = bridge?.feed(Self.character(String(character)))
        }
        return output?.candidates.map(\.text) ?? []
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
