import Foundation

enum PrivatePinyinPackageDownloadError: Error, Equatable {
    case cancelled
    case invalidResponse
    case invalidSize
    case networkFailure
    case storageFailure
}

final class PrivatePinyinPackageDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias ProgressHandler = (Int) -> Void
    typealias CompletionHandler = (Result<URL, PrivatePinyinPackageDownloadError>) -> Void

    private let packageURL: URL
    private let allowedHost: String
    private let expectedSize: Int64
    private let destinationFileName: String
    private let progressHandler: ProgressHandler
    private var completionHandler: CompletionHandler?
    private var task: URLSessionDownloadTask?
    private var downloadedPackageURL: URL?
    private var failureOverride: PrivatePinyinPackageDownloadError?
    private var cancellationRequested = false
    private var completed = false
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PrivatePinyin.UpdateDownload"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false

        return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }()

    init(
        packageURL: URL,
        allowedHost: String,
        expectedSize: Int64,
        destinationFileName: String,
        progressHandler: @escaping ProgressHandler,
        completionHandler: @escaping CompletionHandler
    ) {
        self.packageURL = packageURL
        self.allowedHost = allowedHost.lowercased()
        self.expectedSize = expectedSize
        self.destinationFileName = destinationFileName
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
        super.init()
    }

    func start() {
        guard task == nil,
              expectedSize > 0,
              destinationFileName == (destinationFileName as NSString).lastPathComponent,
              destinationFileName.lowercased().hasSuffix(".pkg"),
              isAllowedPackageURL(packageURL)
        else {
            complete(.failure(.invalidResponse))
            return
        }

        var request = URLRequest(url: packageURL)
        request.httpMethod = "GET"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let downloadTask = session.downloadTask(with: request)
        task = downloadTask
        downloadTask.resume()
    }

    func cancel() {
        delegateQueue.addOperation { [weak self] in
            guard let self, !self.completed else {
                return
            }
            self.cancellationRequested = true
            self.task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, isAllowedPackageURL(url) else {
            failureOverride = .invalidResponse
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard downloadTask === task, !completed else {
            return
        }
        if totalBytesWritten > expectedSize ||
            (totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite != expectedSize)
        {
            failureOverride = .invalidSize
            downloadTask.cancel()
            return
        }

        let progress = Int(min(100, (Double(totalBytesWritten) / Double(expectedSize)) * 100))
        DispatchQueue.main.async { [progressHandler] in
            progressHandler(progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard downloadTask === task, !completed else {
            return
        }
        guard let response = downloadTask.response as? HTTPURLResponse,
              response.statusCode == 200,
              let finalURL = response.url,
              isAllowedPackageURL(finalURL)
        else {
            failureOverride = .invalidResponse
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            guard let size = (attributes[.size] as? NSNumber)?.int64Value,
                  size == expectedSize
            else {
                failureOverride = .invalidSize
                return
            }
            downloadedPackageURL = try moveToPrivateCache(location)
        } catch {
            failureOverride = .storageFailure
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard task === self.task, !completed else {
            return
        }

        if let failureOverride {
            removeDownloadedPackageIfNeeded()
            complete(.failure(failureOverride))
        } else if cancellationRequested {
            removeDownloadedPackageIfNeeded()
            complete(.failure(.cancelled))
        } else if error != nil {
            removeDownloadedPackageIfNeeded()
            complete(.failure(.networkFailure))
        } else if let downloadedPackageURL {
            complete(.success(downloadedPackageURL))
        } else {
            complete(.failure(.invalidResponse))
        }
    }

    private func moveToPrivateCache(_ temporaryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw PrivatePinyinPackageDownloadError.storageFailure
        }
        let directory = cachesURL
            .appendingPathComponent("PrivatePinyin", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let directoryAttributes = try fileManager.attributesOfItem(atPath: directory.path)
        guard directoryAttributes[.type] as? FileAttributeType == .typeDirectory else {
            throw PrivatePinyinPackageDownloadError.storageFailure
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )

        for item in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) where item.pathExtension.lowercased() == "pkg" {
            try? fileManager.removeItem(at: item)
        }

        let destination = directory.appendingPathComponent(destinationFileName, isDirectory: false)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: destination.path
        )
        return destination
    }

    private func removeDownloadedPackageIfNeeded() {
        guard let downloadedPackageURL else {
            return
        }
        try? FileManager.default.removeItem(at: downloadedPackageURL)
        self.downloadedPackageURL = nil
    }

    private func isAllowedPackageURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" &&
            url.host?.lowercased() == allowedHost &&
            url.user == nil &&
            url.password == nil &&
            url.fragment == nil &&
            (url.port == nil || url.port == 443) &&
            url.pathExtension.lowercased() == "pkg"
    }

    private func complete(_ result: Result<URL, PrivatePinyinPackageDownloadError>) {
        guard !completed else {
            return
        }
        completed = true
        task = nil
        let callback = completionHandler
        completionHandler = nil
        session.finishTasksAndInvalidate()
        DispatchQueue.main.async {
            callback?(result)
        }
    }
}
