import Foundation

enum PrivatePinyinSettingsStore {
    private static let macOSCandidatePageSize = 9
    private static let previousDefaultCandidatePageSize = 5

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
            }
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
