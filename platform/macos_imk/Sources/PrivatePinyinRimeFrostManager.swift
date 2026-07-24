import Foundation

enum PrivatePinyinRimeFrostState: Equatable {
    case idle
    case downloading(Int)
    case checking
    case pendingReview(String)
    case failed(String)
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
    static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]
}

extension Notification.Name {
    static let privatePinyinRimeFrostStateChanged =
        Notification.Name("PrivatePinyinRimeFrostStateChanged")
}

final class PrivatePinyinRimeFrostManager: NSObject, URLSessionDownloadDelegate {
    static let shared = PrivatePinyinRimeFrostManager()

    private(set) var state: PrivatePinyinRimeFrostState = .idle {
        didSet {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .privatePinyinRimeFrostStateChanged,
                    object: self
                )
            }
        }
    }

    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
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
        guard downloadTask == nil else {
            return
        }
        self.completion = completion
        state = .downloading(0)
        let task = session.downloadTask(with: PrivatePinyinRimeFrostCatalog.archiveURL)
        downloadTask = task
        task.resume()
    }

    func checkLatestRelease() {
        guard downloadTask == nil else {
            return
        }
        state = .checking
        var request = URLRequest(url: PrivatePinyinRimeFrostCatalog.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("StationCat-PrivatePinyin", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  http.url?.host?.lowercased() == "api.github.com",
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String
            else {
                self.state = .failed("无法检查白霜拼音版本，请稍后重试。")
                return
            }
            let normalized = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            self.state = normalized == PrivatePinyinRimeFrostCatalog.approvedVersion
                ? .idle
                : .pendingReview(normalized)
        }.resume()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let denominator = max(totalBytesExpectedToWrite, PrivatePinyinRimeFrostCatalog.archiveBytes)
        state = .downloading(Int(min(100, totalBytesWritten * 100 / max(1, denominator))))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let host = request.url?.host?.lowercased()
        completionHandler(
            host.map(PrivatePinyinRimeFrostCatalog.allowedDownloadHosts.contains) == true
                ? request
                : nil
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard downloadTask === self.downloadTask,
              let response = downloadTask.response as? HTTPURLResponse,
              response.statusCode == 200,
              let host = response.url?.host?.lowercased(),
              PrivatePinyinRimeFrostCatalog.allowedDownloadHosts.contains(host)
        else {
            finish(.failure(URLError(.badServerResponse)))
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
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard task === downloadTask, let error else {
            return
        }
        finish(.failure(error))
    }

    private func finish(_ result: Result<URL, Error>) {
        let callback = completion
        completion = nil
        downloadTask = nil
        switch result {
        case .success:
            state = .idle
        case .failure:
            state = .failed("无法从白霜拼音官方 GitHub Release 下载。")
        }
        DispatchQueue.main.async {
            callback?(result)
        }
    }
}
