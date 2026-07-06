import Foundation
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

final class PinyinCoreBridge {
    private var engine: OpaquePointer?
    private var session: OpaquePointer?
    private let settingsPath: String?

    init?() {
        settingsPath = PrivatePinyinSettingsStore.ensureSettingsFile()
        guard let (engine, session) = Self.openEngine(settingsPath: settingsPath) else {
            return nil
        }
        self.engine = engine
        self.session = session
    }

    deinit {
        close()
    }

    func reload() -> Bool {
        close()
        guard let (engine, session) = Self.openEngine(settingsPath: settingsPath) else {
            return false
        }
        self.engine = engine
        self.session = session
        return true
    }

    func feed(_ mappedKey: MappedKey) -> PinyinOutput? {
        guard let session else {
            return nil
        }

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
        return takeOutput(ime_session_commit_candidate(session, Int32(index)))
    }

    func resetSession() -> PinyinOutput? {
        guard let session else {
            return nil
        }
        return takeOutput(ime_session_reset(session))
    }

    func clearUserLexicon() -> Bool {
        guard let engine else {
            return false
        }
        return ime_engine_clear_user_lexicon(engine) != 0
    }

    func exportUserLexicon(to path: String) -> Bool {
        guard let engine else {
            return false
        }
        return path.withCString { pathPointer in
            ime_engine_export_user_lexicon(engine, pathPointer) != 0
        }
    }

    private static func openEngine(settingsPath: String?) -> (OpaquePointer, OpaquePointer)? {
        let engine: OpaquePointer?
        if let settingsPath {
            engine = settingsPath.withCString { pathPointer in
                ime_engine_new(pathPointer)
            }
        } else {
            engine = ime_engine_new(nil)
        }

        guard let engine else {
            return nil
        }
        guard let session = ime_session_new(engine) else {
            ime_engine_free(engine)
            return nil
        }
        return (engine, session)
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
