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

        let backupDate = PrivatePinyinSettingsStore.importedLexiconSourceDescriptor(
            for: URL(fileURLWithPath: "/tmp/backup-2024.01.02/rime-ice/cn_dicts/8105.dict.yaml")
        )
        require(backupDate.displayName == "雾凇拼音", "known rime-ice dictionary stays recognized")
        require(backupDate.version == nil, "ancestor backup dates are not recorded as rime-ice versions")

        let descendantDate = PrivatePinyinSettingsStore.importedLexiconSourceDescriptor(
            for: URL(fileURLWithPath: "/tmp/rime-ice/releases/2026.03.26/cn_dicts/others.dict.yaml")
        )
        require(descendantDate.version == "2026.03.26", "rime-ice descendant version is retained")

        let custom = PrivatePinyinSettingsStore.importedLexiconSourceDescriptor(
            for: URL(fileURLWithPath: "/tmp/custom/company_terms.dict.yaml")
        )
        require(custom.displayName == "company_terms", "custom dictionary uses a friendly file stem")
        require(custom.sourceKind == "local_file", "custom dictionary remains a local source")
        require(custom.version == nil, "custom dictionary does not invent a version")

        let customInsideRimeIce = PrivatePinyinSettingsStore.importedLexiconSourceDescriptor(
            for: URL(fileURLWithPath: "/tmp/rime-ice-2026.03.26/custom_phrases.dict.yaml")
        )
        require(customInsideRimeIce.displayName == "custom_phrases", "custom dictionary keeps its name")
        require(customInsideRimeIce.sourceKind == "local_file", "directory context does not absorb custom sources")
        require(customInsideRimeIce.version == nil, "custom dictionary does not inherit the rime-ice version")

        print("macOS imported lexicon source tests passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
