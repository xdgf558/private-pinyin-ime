import Foundation
import PrivatePinyinC

enum IosKeyCodeValue {
    static let unknown: Int32 = 0
    static let space: Int32 = 1
    static let enter: Int32 = 2
    static let backspace: Int32 = 3
    static let escape: Int32 = 4
    static let comma: Int32 = 8
    static let period: Int32 = 9
    static let minus: Int32 = 10
    static let equal: Int32 = 11
    static let apostrophe: Int32 = 12
    static let semicolon: Int32 = 13
    static let pageUp: Int32 = 14
    static let pageDown: Int32 = 15
    static let character: Int32 = 100
    static let digit: Int32 = 101
    static let nineKeyDigit: Int32 = 102
}

struct IosPinyinCandidate {
    let text: String
    let pinyin: String
    let score: Double
    let source: String
}

struct IosPinyinOutput {
    let preedit: String
    let commitText: String
    let isEnglishMode: Bool
    let shouldUpdatePreedit: Bool
    let shouldCommit: Bool
    let shouldShowCandidates: Bool
    let candidates: [IosPinyinCandidate]
}

// Constructed on the loader queue, then published to and used only on main.
final class IosPinyinCoreBridge: @unchecked Sendable {
    static let preferredCandidatePageSize = 9
    private static let fallbackCandidatePageSize = 5
    private static let bytesPerMiB: UInt64 = 1024 * 1024
    private static let minimumAvailableMemoryBytes: UInt64 = 16 * bytesPerMiB
    private static let iosAiPlatform = Int32(IME_AI_PLATFORM_IOS.rawValue)
    private var engine: OpaquePointer?
    private var session: OpaquePointer?
    let candidatePageSize: Int
    private(set) var isLocalAiEnabled = false

    init?() {
        let settingsPath = IosSettingsStore.ensureSettingsFile()
        guard let engine = Self.openEngine(settingsPath: settingsPath) else {
            return nil
        }
        let physicalMemoryMiB = ProcessInfo.processInfo.physicalMemory / Self.bytesPerMiB
        let availableMemoryBytes = private_pinyin_ios_available_memory_bytes()
        if availableMemoryBytes >= Self.minimumAvailableMemoryBytes {
            isLocalAiEnabled = ime_engine_enable_local_ai(
                engine,
                Self.iosAiPlatform,
                physicalMemoryMiB,
                0
            ) == 1
        }
        guard let session = ime_session_new(engine) else {
            ime_engine_free(engine)
            return nil
        }
        let configuredPageSize = ime_session_set_candidate_page_size(
            session,
            Int32(Self.preferredCandidatePageSize)
        ) == 1
        candidatePageSize = configuredPageSize
            ? Self.preferredCandidatePageSize
            : Self.fallbackCandidatePageSize
#if DEBUG
        if !configuredPageSize {
            print("ios_candidate_page_size_fallback")
        }
#endif
        self.engine = engine
        self.session = session
    }

    deinit {
        close()
    }

    func feed(keyCode: Int32, text: String = "", shift: Bool = false) -> IosPinyinOutput? {
        guard let session else {
            return nil
        }

        return text.withCString { textPointer in
            let event = ImeKeyEvent(
                key_code: keyCode,
                text: textPointer,
                shift: shift ? 1 : 0,
                ctrl: 0,
                alt: 0,
                meta: 0,
                is_repeat: 0,
                timestamp_ms: Int64(Date().timeIntervalSince1970 * 1000.0)
            )
            return takeOutput(ime_session_feed_key(session, event))
        }
    }

    func commitCandidate(index: Int) -> IosPinyinOutput? {
        guard let session else {
            return nil
        }
        return takeOutput(ime_session_commit_candidate(session, Int32(index)))
    }

    func toggleMode() -> IosPinyinOutput? {
        guard let session else {
            return nil
        }
        return takeOutput(ime_session_toggle_mode(session))
    }

    func reset() -> IosPinyinOutput? {
        guard let session else {
            return nil
        }
        return takeOutput(ime_session_reset(session))
    }

    func setSecureInput(_ secureInput: Bool) {
        guard let session else {
            return
        }
        _ = ime_session_set_secure_input(session, secureInput ? 1 : 0)
    }

    private static func openEngine(settingsPath: String?) -> OpaquePointer? {
        let configuredEngine = settingsPath.flatMap { path in
            path.withCString { pathPointer in
                ime_engine_new(pathPointer)
            }
        }
        return configuredEngine ?? ime_engine_new(nil)
    }

    private func close() {
        if let session {
            ime_session_free(session)
            self.session = nil
        }
        if let engine {
            ime_engine_free(engine)
            self.engine = nil
        }
    }

    private func takeOutput(_ outputPointer: UnsafeMutablePointer<ImeOutput>?) -> IosPinyinOutput? {
        guard let outputPointer else {
            return nil
        }
        defer {
            ime_output_free(outputPointer)
        }

        let output = outputPointer.pointee
        var candidates: [IosPinyinCandidate] = []
        if output.candidate_count > 0, let candidatePointer = output.candidates {
            let buffer = UnsafeBufferPointer(
                start: candidatePointer,
                count: Int(output.candidate_count)
            )
            candidates = buffer.map { candidate in
                IosPinyinCandidate(
                    text: string(from: candidate.text),
                    pinyin: string(from: candidate.pinyin),
                    score: candidate.score,
                    source: string(from: candidate.source)
                )
            }
        }

        return IosPinyinOutput(
            preedit: string(from: output.preedit),
            commitText: string(from: output.commit_text),
            isEnglishMode: output.mode == IME_MODE_ENGLISH,
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
