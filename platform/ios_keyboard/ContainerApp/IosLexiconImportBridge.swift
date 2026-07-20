import CryptoKit
import Foundation
import PrivatePinyinC

enum IosLexiconImportError: Error {
    case sharedStorageUnavailable
    case tooManyFiles
    case sourceTooLarge
    case unreadableSource
    case engineUnavailable
    case importFailed
    case downloadFailed
    case invalidDownload
    case integrityCheckFailed
    case partialImport(acceptedRows: Int)
}

enum IosLexiconImportBridge {
    static let reviewedRimeIceDisplayName = "雾凇拼音精选"
    static let reviewedRimeIceVersion = "2026.03.26"
    static let reviewedRimeIceSourceURL = URL(
        string: "https://github.com/iDvel/rime-ice/releases/tag/2026.03.26"
    )!

    private struct ReviewedRimeIceFile {
        let name: String
        let url: String
        let byteCount: Int
        let sha256: String
    }

    private static let maxRimeImportsPerBatch = 8
    private static let maxRimeSourceBytes = 16 * 1024 * 1024
    private static let reviewedRimeIceFiles = [
        ReviewedRimeIceFile(
            name: "8105.dict.yaml",
            url: "https://raw.githubusercontent.com/iDvel/rime-ice/2026.03.26/cn_dicts/8105.dict.yaml",
            byteCount: 114_070,
            sha256: "5968cddbf08f9aab7f56a37f265f7d7af85d5222079e5eebdf1bae94b0cdf67d"
        ),
        ReviewedRimeIceFile(
            name: "41448.dict.yaml",
            url: "https://raw.githubusercontent.com/iDvel/rime-ice/2026.03.26/cn_dicts/41448.dict.yaml",
            byteCount: 387_281,
            sha256: "873df74783f565e01581938b14bdf41b4e03a8834791f8778ebcbd70054a26d0"
        ),
        ReviewedRimeIceFile(
            name: "others.dict.yaml",
            url: "https://raw.githubusercontent.com/iDvel/rime-ice/2026.03.26/cn_dicts/others.dict.yaml",
            byteCount: 16_862,
            sha256: "6a6b1a77d94c7cdf9203cf426e67f350215d2d73259fe3769c97d2a18f521c28"
        ),
    ]

    static func importRimeLexicons(
        from sourceURLs: [URL],
        sourceOverride: IosImportedLexiconSource? = nil
    ) throws -> Int {
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
        var importedURLs: [URL] = []
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
                importedURLs.append(sourceURL)
            }
            recordImportedSources(
                importedURLs,
                sourceOverride: sourceOverride,
                isPartial: false
            )
            IosSettingsStore.recordRimeImportStatus("success")
            return acceptedRows
        } catch {
            if acceptedRows > 0 {
                recordImportedSources(
                    importedURLs,
                    sourceOverride: sourceOverride,
                    isPartial: true
                )
                IosSettingsStore.recordRimeImportStatus("partial")
                throw IosLexiconImportError.partialImport(acceptedRows: acceptedRows)
            }
            IosSettingsStore.recordRimeImportStatus("failure")
            throw error
        }
    }

    static func importReviewedRimeIce(
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard IosSettingsStore.usesAppGroupStorage else {
            completion(.failure(IosLexiconImportError.sharedStorageUnavailable))
            return
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "private-pinyin-rime-ice-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            completion(.failure(IosLexiconImportError.unreadableSource))
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        let session = URLSession(configuration: configuration)
        downloadReviewedRimeIceFile(
            at: 0,
            session: session,
            temporaryDirectory: temporaryDirectory,
            downloadedURLs: [],
            completion: completion
        )
    }

    private static func downloadReviewedRimeIceFile(
        at index: Int,
        session: URLSession,
        temporaryDirectory: URL,
        downloadedURLs: [URL],
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard index < reviewedRimeIceFiles.count else {
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<Int, Error>
                do {
                    let acceptedRows = try importRimeLexicons(
                        from: downloadedURLs,
                        sourceOverride: IosImportedLexiconSource(
                            displayName: reviewedRimeIceDisplayName,
                            sourceKind: "reviewed_rime_ice",
                            version: reviewedRimeIceVersion
                        )
                    )
                    result = .success(acceptedRows)
                } catch {
                    result = .failure(error)
                }
                finishReviewedRimeIceImport(
                    result,
                    session: session,
                    temporaryDirectory: temporaryDirectory,
                    completion: completion
                )
            }
            return
        }

        let item = reviewedRimeIceFiles[index]
        guard
            let url = URL(string: item.url),
            url.scheme == "https",
            url.host == "raw.githubusercontent.com"
        else {
            finishReviewedRimeIceImport(
                .failure(IosLexiconImportError.invalidDownload),
                session: session,
                temporaryDirectory: temporaryDirectory,
                completion: completion
            )
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let data else {
                finishReviewedRimeIceImport(
                    .failure(IosLexiconImportError.downloadFailed),
                    session: session,
                    temporaryDirectory: temporaryDirectory,
                    completion: completion
                )
                return
            }
            guard
                let response = response as? HTTPURLResponse,
                response.statusCode == 200,
                response.url?.scheme == "https",
                response.url?.host == "raw.githubusercontent.com",
                data.count == item.byteCount,
                data.count <= maxRimeSourceBytes
            else {
                finishReviewedRimeIceImport(
                    .failure(IosLexiconImportError.invalidDownload),
                    session: session,
                    temporaryDirectory: temporaryDirectory,
                    completion: completion
                )
                return
            }
            guard sha256Hex(data) == item.sha256 else {
                finishReviewedRimeIceImport(
                    .failure(IosLexiconImportError.integrityCheckFailed),
                    session: session,
                    temporaryDirectory: temporaryDirectory,
                    completion: completion
                )
                return
            }

            let destinationURL = temporaryDirectory.appendingPathComponent(
                item.name,
                isDirectory: false
            )
            do {
                try data.write(to: destinationURL, options: [.atomic])
            } catch {
                finishReviewedRimeIceImport(
                    .failure(IosLexiconImportError.unreadableSource),
                    session: session,
                    temporaryDirectory: temporaryDirectory,
                    completion: completion
                )
                return
            }

            downloadReviewedRimeIceFile(
                at: index + 1,
                session: session,
                temporaryDirectory: temporaryDirectory,
                downloadedURLs: downloadedURLs + [destinationURL],
                completion: completion
            )
        }.resume()
    }

    private static func finishReviewedRimeIceImport(
        _ result: Result<Int, Error>,
        session: URLSession,
        temporaryDirectory: URL,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        session.finishTasksAndInvalidate()
        try? FileManager.default.removeItem(at: temporaryDirectory)
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private static func recordImportedSources(
        _ sourceURLs: [URL],
        sourceOverride: IosImportedLexiconSource?,
        isPartial: Bool
    ) {
        let sources: [IosImportedLexiconSource]
        if let sourceOverride {
            sources = [IosImportedLexiconSource(
                displayName: isPartial
                    ? "\(sourceOverride.displayName)（部分）"
                    : sourceOverride.displayName,
                sourceKind: sourceOverride.sourceKind,
                version: sourceOverride.version
            )]
        } else {
            sources = sourceURLs.map { url in
                IosImportedLexiconSource(
                    displayName: url.lastPathComponent,
                    sourceKind: "local_file",
                    version: nil
                )
            }
        }
        _ = IosSettingsStore.recordImportedLexiconSources(sources)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}
