import Foundation

enum PrivatePinyinSettingsStore {
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

    static func ensureSettingsFile() -> String? {
        do {
            try FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: settingsURL.path) {
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
        [
            "default_mode": "Chinese",
            "toggle_key": "Shift",
            "candidate_page_size": 5,
            "enable_prediction": true,
            "enable_user_learning": true,
            "strict_privacy_mode": false,
            "user_lexicon_path": userLexiconURL.path,
            "fuzzy_pinyin": [
                "zh_z": false,
                "ch_c": false,
                "sh_s": false,
                "n_l": false,
                "an_ang": false,
                "en_eng": false,
                "in_ing": false,
            ],
            "theme": "system",
            "candidate_font_size": 14,
        ]
    }

    private static func readSettings() -> [String: Any] {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let object = try? JSONSerialization.jsonObject(with: data),
            let settings = object as? [String: Any]
        else {
            return defaultSettings()
        }

        return settings
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
}
