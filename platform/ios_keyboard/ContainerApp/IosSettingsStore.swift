import Foundation

enum IosSettingsStore {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivatePinyin", isDirectory: true)
    }

    static var userLexiconURL: URL {
        supportDirectory.appendingPathComponent("user_lexicon.sqlite", isDirectory: false)
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
}
