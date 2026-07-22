import Foundation

struct PrivatePinyinImportedLexiconSource {
    let displayName: String
    let sourceKind: String
    let version: String?
}

enum PrivatePinyinSettingsStore {
    private static let macOSCandidatePageSize = 9
    private static let previousDefaultCandidatePageSize = 5
    private static let importedLexiconManifestSchemaVersion = 1
    private static let maximumRecordedImportedSources = 32
    private static let knownRimeIceDictionaryNames: Set<String> = [
        "8105",
        "41448",
        "base",
        "ext",
        "others",
        "tencent",
    ]

    private struct ImportedLexiconManifest: Codable {
        let schemaVersion: Int
        var sources: [ImportedLexiconSource]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case sources
        }
    }

    private struct ImportedLexiconSource: Codable {
        let displayName: String
        let sourceKind: String
        let version: String?
        let importedAt: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case sourceKind = "source_kind"
            case version
            case importedAt = "imported_at"
        }
    }

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("PrivatePinyin", isDirectory: true)
    }

    static var settingsURL: URL {
        supportDirectory.appendingPathComponent("settings.json", isDirectory: false)
    }

    static var userLexiconURL: URL {
        supportDirectory.appendingPathComponent("user_lexicon.sqlite", isDirectory: false)
    }

    static var importedLexiconURL: URL {
        supportDirectory.appendingPathComponent("imported_lexicon.tsv", isDirectory: false)
    }

    static var importedLexiconManifestURL: URL {
        supportDirectory.appendingPathComponent(
            "imported_lexicon_manifest.json",
            isDirectory: false
        )
    }

    static func ensureSettingsFile() -> String? {
        do {
            try FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: settingsURL.path) {
                try repairRuntimeSettingsIfNeeded()
            } else {
                try write(settings: defaultSettings())
            }

            return settingsURL.path
        } catch {
            return nil
        }
    }

    static func isStrictPrivacyModeEnabled() -> Bool {
        readSettings()["strict_privacy_mode"] as? Bool ?? false
    }

    static func settingsSnapshot() -> [String: Any] {
        readSettings()
    }

    static func setStrictPrivacyMode(_ enabled: Bool) -> Bool {
        updateSettings { settings in
            settings["strict_privacy_mode"] = enabled
            if enabled {
                settings["enable_user_learning"] = false
                var ai = settings["ai"] as? [String: Any] ?? [:]
                ai["enable_short_completion"] = false
                ai["enable_rewrite"] = false
                ai["enable_translation"] = false
                settings["ai"] = ai
            }
        }
    }

    static func isWriterActionsEnabled(settings: [String: Any]? = nil) -> Bool {
        let settings = settings ?? readSettings()
        guard settings["strict_privacy_mode"] as? Bool != true,
              let ai = settings["ai"] as? [String: Any] else {
            return false
        }
        return ai["enable_rewrite"] as? Bool == true
            && ai["enable_translation"] as? Bool == true
    }

    static func setWriterActionsEnabled(_ enabled: Bool) -> Bool {
        updateSettings { settings in
            let strictPrivacy = settings["strict_privacy_mode"] as? Bool ?? false
            var ai = settings["ai"] as? [String: Any] ?? [:]
            ai["enable_short_completion"] = false
            ai["enable_rewrite"] = enabled && !strictPrivacy
            ai["enable_translation"] = enabled && !strictPrivacy
            settings["ai"] = ai
        }
    }

    static func importedLexiconSummaryText() -> String {
        guard FileManager.default.fileExists(atPath: importedLexiconURL.path) else {
            return "当前导入词库：尚未导入"
        }
        guard let manifest = readImportedLexiconManifest(), !manifest.sources.isEmpty else {
            return "当前导入词库：本地词库（旧版未记录来源，重新导入可识别）"
        }

        let names = manifest.sources.map { source in
            if let version = source.version, !version.isEmpty {
                return "\(source.displayName) \(version)"
            }
            return source.displayName
        }
        let visible = names.prefix(3).joined(separator: "、")
        let remainder = names.count > 3 ? " 等 \(names.count) 项" : ""
        return "当前导入词库：\(visible)\(remainder)"
    }

    static func importedLexiconSourceDescriptor(
        for sourceURL: URL
    ) -> PrivatePinyinImportedLexiconSource {
        let components = sourceURL.pathComponents
        let rimeIceComponentIndex = components.firstIndex(where: isRimeIcePathComponent)
        let dictionaryName = friendlyDictionaryName(for: sourceURL)
        let isKnownRimeIceDictionary = knownRimeIceDictionaryNames.contains(
            dictionaryName.lowercased()
        )

        if let rimeIceComponentIndex, isKnownRimeIceDictionary {
            return PrivatePinyinImportedLexiconSource(
                displayName: "雾凇拼音",
                sourceKind: "rime_ice_local",
                version: versionString(in: components[rimeIceComponentIndex...])
            )
        }

        return PrivatePinyinImportedLexiconSource(
            displayName: friendlyDictionaryName(for: sourceURL),
            sourceKind: "local_file",
            version: nil
        )
    }

    @discardableResult
    static func recordImportedLexiconSources(
        _ descriptors: [PrivatePinyinImportedLexiconSource]
    ) -> Bool {
        guard !descriptors.isEmpty else {
            return true
        }

        var manifest = readImportedLexiconManifest() ?? ImportedLexiconManifest(
            schemaVersion: importedLexiconManifestSchemaVersion,
            sources: []
        )
        let importedAt = ISO8601DateFormatter().string(from: Date())
        for descriptor in descriptors {
            let displayName = descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty else {
                continue
            }
            manifest.sources.removeAll { source in
                source.displayName == displayName
                    && source.sourceKind == descriptor.sourceKind
                    && source.version == descriptor.version
            }
            manifest.sources.append(ImportedLexiconSource(
                displayName: displayName,
                sourceKind: descriptor.sourceKind,
                version: descriptor.version,
                importedAt: importedAt
            ))
        }
        if manifest.sources.count > maximumRecordedImportedSources {
            manifest.sources.removeFirst(manifest.sources.count - maximumRecordedImportedSources)
        }

        do {
            try writeImportedLexiconManifest(manifest)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func clearImportedLexiconManifest() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: importedLexiconManifestURL.path) {
                try FileManager.default.removeItem(at: importedLexiconManifestURL)
            }
            return true
        } catch {
            return false
        }
    }

    static func updateSettings(_ update: (inout [String: Any]) -> Void) -> Bool {
        var settings = readSettings()
        update(&settings)
        do {
            try write(settings: settings)
            return true
        } catch {
            return false
        }
    }

    private static func defaultSettings() -> [String: Any] {
        var settings = bundledDefaultSettings() ?? [
            "enable_prediction": true,
            "enable_user_learning": true,
            "strict_privacy_mode": false,
        ]
        settings["candidate_page_size"] = macOSCandidatePageSize
        settings["user_lexicon_path"] = userLexiconURL.path
        settings["imported_lexicon_path"] = importedLexiconURL.path
        return settings
    }

    private static func readSettings() -> [String: Any] {
        readSettingsFile() ?? defaultSettings()
    }

    private static func readSettingsFile() -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let object = try? JSONSerialization.jsonObject(with: data),
            let settings = object as? [String: Any]
        else {
            return nil
        }

        return settings
    }

    private static func repairRuntimeSettingsIfNeeded() throws {
        guard var settings = readSettingsFile() else {
            try write(settings: defaultSettings())
            return
        }

        var needsWrite = false
        let pageSize = (settings["candidate_page_size"] as? NSNumber)?.intValue
        if pageSize == nil || pageSize == previousDefaultCandidatePageSize {
            settings["candidate_page_size"] = macOSCandidatePageSize
            needsWrite = true
        }
        let configuredUserLexiconPath = (settings["user_lexicon_path"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if configuredUserLexiconPath?.isEmpty != false {
            settings["user_lexicon_path"] = userLexiconURL.path
            needsWrite = true
        }
        if settings["imported_lexicon_path"] as? String != importedLexiconURL.path {
            settings["imported_lexicon_path"] = importedLexiconURL.path
            needsWrite = true
        }

        if needsWrite {
            try write(settings: settings)
        }
    }

    private static func write(settings: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        let tempURL = settingsURL.deletingLastPathComponent()
            .appendingPathComponent("settings.json.tmp", isDirectory: false)
        try data.write(to: tempURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            _ = try FileManager.default.replaceItemAt(
                settingsURL,
                withItemAt: tempURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: tempURL, to: settingsURL)
        }
    }

    private static func readImportedLexiconManifest() -> ImportedLexiconManifest? {
        guard
            let data = try? Data(contentsOf: importedLexiconManifestURL),
            let manifest = try? JSONDecoder().decode(ImportedLexiconManifest.self, from: data),
            manifest.schemaVersion == importedLexiconManifestSchemaVersion
        else {
            return nil
        }
        return manifest
    }

    private static func writeImportedLexiconManifest(
        _ manifest: ImportedLexiconManifest
    ) throws {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: importedLexiconManifestURL,
            options: [.atomic]
        )
    }

    private static func friendlyDictionaryName(for sourceURL: URL) -> String {
        var name = sourceURL.lastPathComponent
        let suffixes = [".dict.yaml", ".dict.yml", ".yaml", ".yml", ".dict"]
        for suffix in suffixes where name.lowercased().hasSuffix(suffix) {
            name.removeLast(suffix.count)
            break
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "本地 Rime 词库" : trimmed
    }

    private static func isRimeIcePathComponent(_ component: String) -> Bool {
        let normalized = component
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return normalized.contains("rime-ice")
            || component.contains("雾凇")
            || component.contains("霧凇")
    }

    private static func versionString(
        in sourceComponents: ArraySlice<String>
    ) -> String? {
        let pattern = #"(?<!\d)(20\d{2})[._-](\d{1,2})[._-](\d{1,2})(?!\d)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        for component in sourceComponents {
            guard
                let match = expression.firstMatch(
                    in: component,
                    range: NSRange(component.startIndex..., in: component)
                ),
                match.numberOfRanges == 4,
                let yearRange = Range(match.range(at: 1), in: component),
                let monthRange = Range(match.range(at: 2), in: component),
                let dayRange = Range(match.range(at: 3), in: component)
            else {
                continue
            }
            return "\(component[yearRange]).\(component[monthRange]).\(component[dayRange])"
        }
        return nil
    }

    private static func bundledDefaultSettings() -> [String: Any]? {
        for url in defaultSettingsTemplateURLs() {
            guard
                let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data),
                let settings = object as? [String: Any]
            else {
                continue
            }
            return settings
        }
        return nil
    }

    private static func defaultSettingsTemplateURLs() -> [URL] {
        var urls: [URL] = []
        if let bundled = Bundle.main.url(forResource: "default_settings", withExtension: "json") {
            urls.append(bundled)
        }

        let sourceTreeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("default_settings.json", isDirectory: false)
        urls.append(sourceTreeURL)
        return urls
    }
}
