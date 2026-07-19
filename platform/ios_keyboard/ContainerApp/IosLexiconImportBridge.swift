import Foundation
import PrivatePinyinC

enum IosLexiconImportError: Error {
    case sharedStorageUnavailable
    case tooManyFiles
    case sourceTooLarge
    case unreadableSource
    case engineUnavailable
    case importFailed
    case partialImport(acceptedRows: Int)
}

enum IosLexiconImportBridge {
    private static let maxRimeImportsPerBatch = 8
    private static let maxRimeSourceBytes = 16 * 1024 * 1024

    static func importRimeLexicons(from sourceURLs: [URL]) throws -> Int {
        guard IosSettingsStore.usesAppGroupStorage else {
            throw IosLexiconImportError.sharedStorageUnavailable
        }
        guard !sourceURLs.isEmpty else {
            return 0
        }
        guard sourceURLs.count <= maxRimeImportsPerBatch else {
            throw IosLexiconImportError.tooManyFiles
        }
        guard let settingsPath = IosSettingsStore.ensureSettingsFile() else {
            throw IosLexiconImportError.sharedStorageUnavailable
        }
        guard let engine = settingsPath.withCString({ ime_engine_new($0) }) else {
            IosSettingsStore.recordRimeImportStatus("failure")
            throw IosLexiconImportError.engineUnavailable
        }
        defer {
            ime_engine_free(engine)
        }

        var acceptedRows = 0
        do {
            for sourceURL in sourceURLs {
                let values: URLResourceValues
                do {
                    values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
                } catch {
                    throw IosLexiconImportError.unreadableSource
                }
                if let fileSize = values.fileSize, fileSize > maxRimeSourceBytes {
                    throw IosLexiconImportError.sourceTooLarge
                }

                let result = sourceURL.path.withCString { sourcePath in
                    ime_engine_import_rime_lexicon(engine, sourcePath)
                }
                guard result >= 0 else {
                    throw IosLexiconImportError.importFailed
                }
                acceptedRows += Int(result)
            }
            IosSettingsStore.recordRimeImportStatus("success")
            return acceptedRows
        } catch {
            if acceptedRows > 0 {
                IosSettingsStore.recordRimeImportStatus("partial")
                throw IosLexiconImportError.partialImport(acceptedRows: acceptedRows)
            }
            IosSettingsStore.recordRimeImportStatus("failure")
            throw error
        }
    }
}
