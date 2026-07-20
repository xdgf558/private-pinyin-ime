import Carbon
import Foundation
import OSLog
import PrivatePinyinC

struct PinyinCandidate {
    let text: String
    let pinyin: String
    let score: Double
    let source: String
}

struct PinyinOutput {
    let preedit: String
    let commitText: String
    let shouldUpdatePreedit: Bool
    let shouldCommit: Bool
    let shouldShowCandidates: Bool
    let candidates: [PinyinCandidate]
}

private struct PinyinEngineFileFingerprint: Equatable {
    let exists: Bool
    let size: UInt64
    let modificationDate: TimeInterval

    init(path: String?) {
        guard
            let path,
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else {
            exists = false
            size = 0
            modificationDate = 0
            return
        }

        exists = true
        size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        modificationDate = (attributes[.modificationDate] as? Date)?
            .timeIntervalSinceReferenceDate ?? 0
    }
}

private struct PinyinEngineConfigurationFingerprint: Equatable {
    let settingsPath: String?
    let settingsData: Data?
    let importedLexicon: PinyinEngineFileFingerprint

    init(settingsPath: String?) {
        let normalizedSettingsPath = settingsPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        let settingsData = normalizedSettingsPath.flatMap(FileManager.default.contents(atPath:))
        let importedLexiconPath = settingsData.flatMap { data -> String? in
            guard
                let object = try? JSONSerialization.jsonObject(with: data),
                let settings = object as? [String: Any]
            else {
                return nil
            }
            return settings["imported_lexicon_path"] as? String
        }

        self.settingsPath = normalizedSettingsPath
        self.settingsData = settingsData
        importedLexicon = PinyinEngineFileFingerprint(path: importedLexiconPath)
    }
}

// InputMethodKit creates one controller per client application. Keep immutable engine resources
// process-wide while every controller retains its own composition session.
private final class SharedPinyinEnginePool {
    static let shared = SharedPinyinEnginePool()
    private static let logger = Logger(
        subsystem: "com.privatepinyin.inputmethod.PrivatePinyin",
        category: "shared-engine"
    )

    private let lock = NSLock()
    private var engine: OpaquePointer?
    private var loadedFingerprint: PinyinEngineConfigurationFingerprint?
    private var failedFingerprint: PinyinEngineConfigurationFingerprint?
    private var engineLoadCount = 0

    deinit {
        if let engine {
            ime_engine_free(engine)
        }
    }

    func makeSession(settingsPath: String?) -> OpaquePointer? {
        lock.lock()
        defer { lock.unlock() }
        guard let engine = ensureEngineLocked(settingsPath: settingsPath) else {
            return nil
        }
        return ime_session_new(engine)
    }

    func withEngine<T>(settingsPath: String?, _ operation: (OpaquePointer) -> T) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let engine = ensureEngineLocked(settingsPath: settingsPath) else {
            return nil
        }
        return operation(engine)
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return engineLoadCount
    }

    private func ensureEngineLocked(settingsPath: String?) -> OpaquePointer? {
        let requestedFingerprint = PinyinEngineConfigurationFingerprint(
            settingsPath: settingsPath
        )
        if let engine,
           loadedFingerprint == requestedFingerprint
            || failedFingerprint == requestedFingerprint
        {
            return engine
        }

        // Keep the previous snapshot alive until replacement succeeds. This intentionally
        // permits a short two-snapshot memory peak so active clients retain working input
        // when a changed configuration cannot be loaded.
        guard let replacement = Self.openEngine(settingsPath: settingsPath) else {
            failedFingerprint = requestedFingerprint
            Self.logger.error("error code=shared_engine_rebuild_failed")
            return engine
        }

        let previous = engine
        engine = replacement
        loadedFingerprint = requestedFingerprint
        failedFingerprint = nil
        engineLoadCount += 1
        if let previous {
            ime_engine_free(previous)
        }
        return replacement
    }

    private static func openEngine(settingsPath: String?) -> OpaquePointer? {
        var engine: OpaquePointer?
        if let settingsPath {
            engine = settingsPath.withCString { pathPointer in
                ime_engine_new(pathPointer)
            }
        } else {
            engine = ime_engine_new(nil)
        }
        if engine == nil, settingsPath != nil {
            engine = ime_engine_new(nil)
        }

        guard let engine else {
            return nil
        }
        let physicalMemoryMb = ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
        _ = ime_engine_enable_desktop_ai(engine, 1, physicalMemoryMb, 0)
        return engine
    }
}

final class PinyinCoreBridge {
    private var session: OpaquePointer?
    private let settingsPath: String?

    init?() {
        let settingsPath = PrivatePinyinSettingsStore.ensureSettingsFile()
        self.settingsPath = settingsPath
        guard let session = SharedPinyinEnginePool.shared.makeSession(
            settingsPath: settingsPath
        ) else {
            return nil
        }
        self.session = session
    }

    init?(settingsPathForTesting settingsPath: String?) {
        self.settingsPath = settingsPath
        guard let session = SharedPinyinEnginePool.shared.makeSession(
            settingsPath: settingsPath
        ) else {
            return nil
        }
        self.session = session
    }

    deinit {
        close()
    }

    func reload() -> Bool {
        guard let replacement = SharedPinyinEnginePool.shared.makeSession(
            settingsPath: settingsPath
        ) else {
            return false
        }
        let previous = session
        session = replacement
        if let previous {
            ime_session_free(previous)
        }
        return true
    }

    func feed(_ mappedKey: MappedKey) -> PinyinOutput? {
        guard let session else {
            return nil
        }
        syncSecureInput(session)

        return mappedKey.text.withCString { textPointer in
            let event = ImeKeyEvent(
                key_code: mappedKey.keyCode,
                text: textPointer,
                shift: mappedKey.shift ? 1 : 0,
                ctrl: mappedKey.ctrl ? 1 : 0,
                alt: mappedKey.alt ? 1 : 0,
                meta: mappedKey.meta ? 1 : 0,
                is_repeat: mappedKey.isRepeat ? 1 : 0,
                timestamp_ms: mappedKey.timestampMs
            )
            return takeOutput(ime_session_feed_key(session, event))
        }
    }

    func commitCandidate(index: Int) -> PinyinOutput? {
        guard let session else {
            return nil
        }
        syncSecureInput(session)
        return takeOutput(ime_session_commit_candidate(session, Int32(index)))
    }

    func resetSession() -> PinyinOutput? {
        guard let session else {
            return nil
        }
        return takeOutput(ime_session_reset(session))
    }

    func clearUserLexicon() -> Bool {
        SharedPinyinEnginePool.shared.withEngine(settingsPath: settingsPath) { engine in
            ime_engine_clear_user_lexicon(engine) != 0
        } ?? false
    }

    func exportUserLexicon(to path: String) -> Bool {
        SharedPinyinEnginePool.shared.withEngine(settingsPath: settingsPath) { engine in
            path.withCString { pathPointer in
                ime_engine_export_user_lexicon(engine, pathPointer) != 0
            }
        } ?? false
    }

    func importRimeLexicon(from path: String) -> Int? {
        guard let imported = SharedPinyinEnginePool.shared.withEngine(
            settingsPath: settingsPath,
            { engine in
                path.withCString { pathPointer in
                    ime_engine_import_rime_lexicon(engine, pathPointer)
                }
            }
        ) else {
            return nil
        }
        return imported >= 0 ? Int(imported) : nil
    }

    func clearImportedLexicon() -> Bool {
        SharedPinyinEnginePool.shared.withEngine(settingsPath: settingsPath) { engine in
            ime_engine_clear_imported_lexicon(engine) != 0
        } ?? false
    }

    static var sharedEngineLoadCountForTesting: Int {
        SharedPinyinEnginePool.shared.loadCount
    }

    private func syncSecureInput(_ session: OpaquePointer) {
        _ = ime_session_set_secure_input(session, IsSecureEventInputEnabled() ? 1 : 0)
    }

    private func close() {
        if let session {
            ime_session_free(session)
            self.session = nil
        }
    }

    private func takeOutput(_ outputPointer: UnsafeMutablePointer<ImeOutput>?) -> PinyinOutput? {
        guard let outputPointer else {
            return nil
        }
        defer {
            ime_output_free(outputPointer)
        }

        let output = outputPointer.pointee
        var candidates: [PinyinCandidate] = []
        if output.candidate_count > 0, let candidatePointer = output.candidates {
            let buffer = UnsafeBufferPointer(
                start: candidatePointer,
                count: Int(output.candidate_count)
            )
            candidates = buffer.map { candidate in
                PinyinCandidate(
                    text: string(from: candidate.text),
                    pinyin: string(from: candidate.pinyin),
                    score: candidate.score,
                    source: string(from: candidate.source)
                )
            }
        }

        return PinyinOutput(
            preedit: string(from: output.preedit),
            commitText: string(from: output.commit_text),
            shouldUpdatePreedit: output.should_update_preedit != 0,
            shouldCommit: output.should_commit != 0,
            shouldShowCandidates: output.should_show_candidates != 0,
            candidates: candidates
        )
    }

    private func string(from pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else {
            return ""
        }
        return String(cString: pointer)
    }
}
