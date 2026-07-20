import Foundation

@main
enum ImportedLexiconSourceTests {
    static func main() {
        let rimeIce = PrivatePinyinSettingsStore.importedLexiconSourceDescriptor(
            for: URL(fileURLWithPath: "/tmp/rime-ice-2026.03.26/cn_dicts/8105.dict.yaml")
        )
        require(rimeIce.displayName == "雾凇拼音", "rime-ice path uses the product name")
        require(rimeIce.sourceKind == "rime_ice_local", "rime-ice path records its source kind")
        require(rimeIce.version == "2026.03.26", "rime-ice path records its visible version")

        let traditionalName = PrivatePinyinSettingsStore.importedLexiconSourceDescriptor(
            for: URL(fileURLWithPath: "/tmp/霧凇拼音/cn_dicts/base.dict.yaml")
        )
        require(traditionalName.displayName == "雾凇拼音", "traditional folder name is recognized")

        let custom = PrivatePinyinSettingsStore.importedLexiconSourceDescriptor(
            for: URL(fileURLWithPath: "/tmp/custom/company_terms.dict.yaml")
        )
        require(custom.displayName == "company_terms", "custom dictionary uses a friendly file stem")
        require(custom.sourceKind == "local_file", "custom dictionary remains a local source")
        require(custom.version == nil, "custom dictionary does not invent a version")

        print("macOS imported lexicon source tests passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
