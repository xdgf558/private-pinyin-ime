import Foundation

enum PrivatePinyinRimeFrostState: Equatable {
    case idle
    case downloading(Int)
    case checking
    case pendingReview(String)
    case failed(String)
}

enum PrivatePinyinRimeFrostManagerError: LocalizedError, Equatable {
    case operationInProgress
    case versionCheckFailed

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            "另一项白霜拼音操作正在进行，请稍后重试。"
        case .versionCheckFailed:
            "无法检查白霜拼音版本，请稍后重试。"
        }
    }
}

enum PrivatePinyinRimeFrostCatalog {
    static let displayName = "白霜拼音核心词库"
    static let approvedVersion = "1.0.4"
    static let archiveBytes: Int64 = 44_008_360
    static let archiveSHA256 = "4f4998ae83f63d757c0a4ace192f69d48265bddfabe231642b73e3739ed0f2f5"
    static let archiveURL = URL(
        string: "https://github.com/gaboolic/rime-frost/releases/download/1.0.4/rime-frost-schemas.zip"
    )!
    static let releaseURL = URL(
        string: "https://github.com/gaboolic/rime-frost/releases/tag/1.0.4"
    )!
    static let licenseURL = URL(
        string: "https://github.com/gaboolic/rime-frost/blob/master/LICENSE"
    )!
    static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/gaboolic/rime-frost/releases/latest"
    )!
    static func isSecureArtifactURL(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" && url?.host?.isEmpty == false
    }
}

extension Notification.Name {
    static let privatePinyinRimeFrostStateChanged =
        Notification.Name("PrivatePinyinRimeFrostStateChanged")
}

final class PrivatePinyinRimeFrostManager: NSObject, URLSessionDownloadDelegate {
    static let shared = PrivatePinyinRimeFrostManager()

    var state: PrivatePinyinRimeFrostState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedState
    }

    private let stateLock = NSLock()
    private var storedState: PrivatePinyinRimeFrostState = .idle
    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var releaseCheckTask: URLSessionDataTask?
    private var releaseCheckID: UUID?
    private var completion: ((Result<URL, Error>) -> Void)?

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = [
            "Accept": "application/octet-stream",
            "User-Agent": "StationCat-PrivatePinyin",
        ]
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func downloadApprovedArchive(
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let task = session.downloadTask(with: PrivatePinyinRimeFrostCatalog.archiveURL)
        stateLock.lock()
        guard downloadTask == nil, releaseCheckTask == nil else {
            stateLock.unlock()
            DispatchQueue.main.async {
                completion(.failure(PrivatePinyinRimeFrostManagerError.operationInProgress))
            }
            return
        }
        self.completion = completion
        downloadTask = task
        stateLock.unlock()
        setState(.downloading(0))
        task.resume()
    }

    func checkLatestRelease(
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: PrivatePinyinRimeFrostCatalog.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("StationCat-PrivatePinyin", forHTTPHeaderField: "User-Agent")
        let requestID = UUID()
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  http.url?.host?.lowercased() == "api.github.com",
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String
            else {
                self.completeReleaseCheck(
                    requestID: requestID,
                    state: .failed("无法检查白霜拼音版本，请稍后重试。"),
                    result: .failure(PrivatePinyinRimeFrostManagerError.versionCheckFailed),
                    completion: completion
                )
                return
            }
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized: String
            if let first = trimmedTag.first, first == "v" || first == "V" {
                normalized = String(trimmedTag.dropFirst())
            } else {
                normalized = trimmedTag
            }
            self.completeReleaseCheck(
                requestID: requestID,
                state: normalized == PrivatePinyinRimeFrostCatalog.approvedVersion
                    ? .idle
                    : .pendingReview(normalized),
                result: .success(normalized),
                completion: completion
            )
        }
        stateLock.lock()
        guard downloadTask == nil, releaseCheckTask == nil else {
            stateLock.unlock()
            DispatchQueue.main.async {
                completion(.failure(PrivatePinyinRimeFrostManagerError.operationInProgress))
            }
            return
        }
        releaseCheckTask = task
        releaseCheckID = requestID
        stateLock.unlock()
        setState(.checking)
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesWritten <= PrivatePinyinRimeFrostCatalog.archiveBytes else {
            downloadTask.cancel()
            finishDownload(
                .failure(URLError(.dataLengthExceedsMaximum)),
                task: downloadTask
            )
            return
        }
        let denominator = PrivatePinyinRimeFrostCatalog.archiveBytes
        updateDownloadProgress(
            Int(min(100, totalBytesWritten * 100 / denominator)),
            task: downloadTask
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(
            PrivatePinyinRimeFrostCatalog.isSecureArtifactURL(request.url) ? request : nil
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard isCurrentDownloadTask(downloadTask),
              let response = downloadTask.response as? HTTPURLResponse,
              response.statusCode == 200,
              PrivatePinyinRimeFrostCatalog.isSecureArtifactURL(response.url)
        else {
            finishDownload(.failure(URLError(.badServerResponse)), task: downloadTask)
            return
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            guard (attributes[.size] as? NSNumber)?.int64Value
                    == PrivatePinyinRimeFrostCatalog.archiveBytes
            else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            let cacheDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PrivatePinyin-RimeFrost", isDirectory: true)
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let destination = cacheDirectory.appendingPathComponent(
                "rime-frost-\(UUID().uuidString).zip",
                isDirectory: false
            )
            try FileManager.default.moveItem(at: location, to: destination)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
            finishDownload(.success(destination), task: downloadTask)
        } catch {
            finishDownload(.failure(error), task: downloadTask)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask, let error else {
            return
        }
        finishDownload(.failure(error), task: downloadTask)
    }

    private func finishDownload(
        _ result: Result<URL, Error>,
        task: URLSessionDownloadTask
    ) {
        stateLock.lock()
        guard task === downloadTask else {
            stateLock.unlock()
            return
        }
        let callback = completion
        completion = nil
        downloadTask = nil
        storedState = switch result {
        case .success:
            .idle
        case .failure:
            .failed("无法从白霜拼音官方 GitHub Release 下载。")
        }
        stateLock.unlock()
        notifyStateChanged()
        DispatchQueue.main.async {
            callback?(result)
        }
    }

    private func completeReleaseCheck(
        requestID: UUID,
        state: PrivatePinyinRimeFrostState,
        result: Result<String, Error>,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        stateLock.lock()
        guard requestID == releaseCheckID else {
            stateLock.unlock()
            return
        }
        releaseCheckTask = nil
        releaseCheckID = nil
        storedState = state
        stateLock.unlock()
        notifyStateChanged()
        DispatchQueue.main.async {
            completion(result)
        }
    }

    private func isCurrentDownloadTask(_ task: URLSessionDownloadTask) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return task === downloadTask
    }

    private func updateDownloadProgress(_ progress: Int, task: URLSessionDownloadTask) {
        stateLock.lock()
        guard task === downloadTask else {
            stateLock.unlock()
            return
        }
        storedState = .downloading(progress)
        stateLock.unlock()
        notifyStateChanged()
    }

    private func setState(_ state: PrivatePinyinRimeFrostState) {
        stateLock.lock()
        storedState = state
        stateLock.unlock()
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .privatePinyinRimeFrostStateChanged,
                object: self
            )
        }
    }
}
