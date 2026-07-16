import Foundation

enum IosKeyboardLayout: String {
    case qwerty
    case nineKey = "nine_key"
}

enum IosSettingsStore {
    private static let fallbackAppGroupIdentifier = "group.com.privatepinyin.ios"
    private static let keyboardCandidatePageSize = 5

    static var appGroupIdentifier: String {
        guard
            let configured = Bundle.main.object(
                forInfoDictionaryKey: "PrivatePinyinAppGroupIdentifier"
            ) as? String,
            configured.hasPrefix("group.")
        else {
            return fallbackAppGroupIdentifier
        }
        return configured
    }

    static var usesAppGroupStorage: Bool {
        appGroupContainerURL != nil
    }

    static let isKeyboardExtension = Bundle.main.object(
        forInfoDictionaryKey: "NSExtension"
    ) != nil

    static var canEnableLearning: Bool {
        usesAppGroupStorage || isKeyboardExtension
    }

    static var supportDirectory: URL {
        let root = appGroupContainerURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return root.appendingPathComponent("PrivatePinyin", isDirectory: true)
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

            if FileManager.default.fileExists(atPath: settingsURL.path) {
                try repairRuntimePathsIfNeeded()
            } else {
                try write(settings: defaultSettings())
            }

            return settingsURL.path
        } catch {
            return nil
        }
    }

    static func isLearningEnabled() -> Bool {
        readSettings()["enable_user_learning"] as? Bool ?? false
    }

    static func setLearningEnabled(_ enabled: Bool) -> Bool {
        if enabled && !canEnableLearning {
            return false
        }

        return updateSettings { settings in
            settings["enable_user_learning"] = enabled
            if enabled {
                settings["strict_privacy_mode"] = false
            }
        }
    }

    static func isPredictionEnabled() -> Bool {
        readSettings()["enable_prediction"] as? Bool ?? true
    }

    static func setPredictionEnabled(_ enabled: Bool) -> Bool {
        updateSettings { settings in
            settings["enable_prediction"] = enabled
        }
    }

    static func keyboardLayout() -> IosKeyboardLayout {
        guard
            let value = readSettings()["ios_keyboard_layout"] as? String,
            let layout = IosKeyboardLayout(rawValue: value)
        else {
            return .qwerty
        }
        return layout
    }

    static func setKeyboardLayout(_ layout: IosKeyboardLayout) -> Bool {
        updateSettings { settings in
            settings["ios_keyboard_layout"] = layout.rawValue
        }
    }

    static func storageDescription() -> String {
        if usesAppGroupStorage {
            return "学习数据仅保存在本机共享容器中。"
        }
        return "当前版本无法使用共享容器，用户学习将保持关闭。"
    }

    static func keyboardStorageDescription(hasFullAccess: Bool) -> String {
        let access = hasFullAccess ? "完全访问已开启" : "完全访问已关闭"
        let storage = usesAppGroupStorage ? "本机共享存储" : "键盘本机存储"
        return "\(access) · \(storage)\n猫栈拼音不连接网络"
    }

    static func clearLocalLexiconArtifacts() throws -> Int {
        let urls = [
            userLexiconURL,
            supportDirectory.appendingPathComponent("user_lexicon.sqlite-wal", isDirectory: false),
            supportDirectory.appendingPathComponent("user_lexicon.sqlite-shm", isDirectory: false),
        ]

        var removed = 0
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    private static let appGroupContainerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )

    private static func repairRuntimePathsIfNeeded() throws {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let object = try? JSONSerialization.jsonObject(with: data),
            var settings = object as? [String: Any]
        else {
            try write(settings: defaultSettings())
            return
        }

        var needsWrite = false
        let expectedPath = userLexiconURL.path
        if settings["user_lexicon_path"] as? String != expectedPath {
            settings["user_lexicon_path"] = expectedPath
            needsWrite = true
        }
        if settings["candidate_page_size"] as? Int != keyboardCandidatePageSize {
            settings["candidate_page_size"] = keyboardCandidatePageSize
            needsWrite = true
        }
        if needsWrite {
            try write(settings: settings)
        }
    }

    private static func defaultSettings() -> [String: Any] {
        var settings = bundledDefaultSettings() ?? [
            "enable_prediction": true,
            "strict_privacy_mode": false,
        ]
        settings["enable_user_learning"] = false
        settings["user_lexicon_path"] = userLexiconURL.path
        settings["candidate_page_size"] = keyboardCandidatePageSize
        settings["ios_keyboard_layout"] = IosKeyboardLayout.qwerty.rawValue
        return settings
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

    private static func updateSettings(_ update: (inout [String: Any]) -> Void) -> Bool {
        _ = ensureSettingsFile()
        var settings = readSettings()
        update(&settings)
        do {
            try write(settings: settings)
            return true
        } catch {
            return false
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
            .appendingPathComponent("settings.json.\(UUID().uuidString).tmp", isDirectory: false)
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
