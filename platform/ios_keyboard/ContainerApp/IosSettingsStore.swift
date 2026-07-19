import Foundation
import CoreFoundation

enum IosKeyboardLayout: String {
    case qwerty
    case nineKey = "nine_key"
}

enum IosChineseScript: String {
    case simplified
    case traditional
}

enum IosChineseTextConverter {
    static func convert(_ text: String, to script: IosChineseScript) -> String {
        guard script == .traditional, !text.isEmpty else {
            return text
        }

        let converted = NSMutableString(string: text)
        guard CFStringTransform(
            converted,
            nil,
            "Simplified-Traditional" as CFString,
            false
        ) else {
            return text
        }
        return converted as String
    }
}

enum IosSettingsStore {
    private static let fallbackAppGroupIdentifier = "group.com.privatepinyin.ios"
    private static let keyboardCandidatePageSize = 9
    private static let keyboardLayoutDefaultsKey = "private_pinyin.ios_keyboard_layout"
    private static let keyboardLayoutUpdatedAtDefaultsKey =
        "private_pinyin.ios_keyboard_layout_updated_at"
    private static let chineseScriptDefaultsKey = "private_pinyin.ios_chinese_script"
    private static let chineseScriptUpdatedAtDefaultsKey =
        "private_pinyin.ios_chinese_script_updated_at"
    private static let lastRimeImportStatusKey = "ios_last_rime_import_status"

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
        let storedSettings = readStoredSettings()
        let storedLayout = (storedSettings?["ios_keyboard_layout"] as? String)
            .flatMap(IosKeyboardLayout.init(rawValue:))
        let storedUpdatedAt = (storedSettings?["ios_keyboard_layout_updated_at"] as? NSNumber)?
            .doubleValue ?? 0
        let localLayout = UserDefaults.standard.string(forKey: keyboardLayoutDefaultsKey)
            .flatMap(IosKeyboardLayout.init(rawValue:))
        let localUpdatedAt = UserDefaults.standard.double(
            forKey: keyboardLayoutUpdatedAtDefaultsKey
        )

        if let storedLayout,
           localLayout == nil || storedUpdatedAt >= localUpdatedAt {
            return storedLayout
        }
        return localLayout ?? storedLayout ?? .qwerty
    }

    static func setKeyboardLayout(_ layout: IosKeyboardLayout) -> Bool {
        let updatedAt = Date().timeIntervalSince1970
        let sharedSaved = updateSettings { settings in
            settings["ios_keyboard_layout"] = layout.rawValue
            settings["ios_keyboard_layout_updated_at"] = updatedAt
        }
        let localSaved = saveLocalPreference(
            layout.rawValue,
            key: keyboardLayoutDefaultsKey,
            updatedAt: updatedAt,
            updatedAtKey: keyboardLayoutUpdatedAtDefaultsKey
        )
        return sharedSaved || localSaved
    }

    static func chineseScript() -> IosChineseScript {
        let storedSettings = readStoredSettings()
        let storedScript = (storedSettings?["ios_chinese_script"] as? String)
            .flatMap(IosChineseScript.init(rawValue:))
        let storedUpdatedAt = (storedSettings?["ios_chinese_script_updated_at"] as? NSNumber)?
            .doubleValue ?? 0
        let localScript = UserDefaults.standard.string(forKey: chineseScriptDefaultsKey)
            .flatMap(IosChineseScript.init(rawValue:))
        let localUpdatedAt = UserDefaults.standard.double(
            forKey: chineseScriptUpdatedAtDefaultsKey
        )

        if let storedScript,
           localScript == nil || storedUpdatedAt >= localUpdatedAt {
            return storedScript
        }
        return localScript ?? storedScript ?? .simplified
    }

    static func setChineseScript(_ script: IosChineseScript) -> Bool {
        let updatedAt = Date().timeIntervalSince1970
        let sharedSaved = updateSettings { settings in
            settings["ios_chinese_script"] = script.rawValue
            settings["ios_chinese_script_updated_at"] = updatedAt
        }
        let localSaved = saveLocalPreference(
            script.rawValue,
            key: chineseScriptDefaultsKey,
            updatedAt: updatedAt,
            updatedAtKey: chineseScriptUpdatedAtDefaultsKey
        )
        return sharedSaved || localSaved
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

    static func rimeImportStatusText() -> String? {
        switch readSettings()[lastRimeImportStatusKey] as? String {
        case "success":
            return "Rime 词库已导入，键盘会使用新的独立词库层。"
        case "partial":
            return "部分 Rime 词库已导入，其他文件需检查后重试。"
        case "failure":
            return "最近一次 Rime 词库导入失败，请确认文件包含明确拼音列。"
        default:
            return nil
        }
    }

    static func clearImportedLexiconArtifacts() throws -> Int {
        var removed = 0
        if FileManager.default.fileExists(atPath: importedLexiconURL.path) {
            try FileManager.default.removeItem(at: importedLexiconURL)
            removed += 1
        }
        _ = updateSettings { settings in
            settings.removeValue(forKey: lastRimeImportStatusKey)
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
        let expectedImportedPath = importedLexiconURL.path
        if settings["imported_lexicon_path"] as? String != expectedImportedPath {
            settings["imported_lexicon_path"] = expectedImportedPath
            needsWrite = true
        }
        if settings["candidate_page_size"] as? Int != keyboardCandidatePageSize {
            settings["candidate_page_size"] = keyboardCandidatePageSize
            needsWrite = true
        }
        let configuredScript = (settings["ios_chinese_script"] as? String)
            .flatMap(IosChineseScript.init(rawValue:))
        if configuredScript == nil {
            settings["ios_chinese_script"] = IosChineseScript.simplified.rawValue
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
        settings["imported_lexicon_path"] = importedLexiconURL.path
        settings["candidate_page_size"] = keyboardCandidatePageSize
        settings["ios_keyboard_layout"] = IosKeyboardLayout.qwerty.rawValue
        settings["ios_chinese_script"] = IosChineseScript.simplified.rawValue
        return settings
    }

    private static func readSettings() -> [String: Any] {
        readStoredSettings() ?? defaultSettings()
    }

    private static func readStoredSettings() -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let object = try? JSONSerialization.jsonObject(with: data),
            let settings = object as? [String: Any]
        else {
            return nil
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

    static func recordRimeImportStatus(_ status: String) {
        _ = updateSettings { settings in
            settings[lastRimeImportStatusKey] = status
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
        try data.write(to: settingsURL, options: [.atomic])
    }

    private static func saveLocalPreference(
        _ value: String,
        key: String,
        updatedAt: TimeInterval,
        updatedAtKey: String
    ) -> Bool {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.set(updatedAt, forKey: updatedAtKey)
        return UserDefaults.standard.string(forKey: key) == value
            && UserDefaults.standard.double(forKey: updatedAtKey) == updatedAt
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
