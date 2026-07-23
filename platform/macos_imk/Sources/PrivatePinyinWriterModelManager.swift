import CryptoKit
import Foundation

extension Notification.Name {
    static let privatePinyinWriterModelStateChanged = Notification.Name(
        "PrivatePinyinWriterModelStateChanged"
    )
}

enum PrivatePinyinWriterModelState: Equatable {
    case notInstalled
    case downloading(Int)
    case verifying
    case installed
    case failed(String)
}

final class PrivatePinyinWriterModelManager: NSObject, URLSessionDownloadDelegate {
    static let shared = PrivatePinyinWriterModelManager()

    static let modelID = "qwen2.5-1.5b-instruct-q4-k-m"
    static let modelFilename = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    static let expectedSize: Int64 = 1_117_320_736
    static let expectedSHA256 = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
    static let downloadURL = URL(
        string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/dd26da440ef0330c47919d1ecae0966d24022222/qwen2.5-1.5b-instruct-q4_k_m.gguf"
    )!

    private(set) var state: PrivatePinyinWriterModelState = .notInstalled {
        didSet {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .privatePinyinWriterModelStateChanged,
                    object: self
                )
            }
        }
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: operationQueue
        )
    }()
    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.privatepinyin.writer-model-download"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var downloadTask: URLSessionDownloadTask?

    private override init() {
        super.init()
        state = Self.quickInstalledCheck() ? .installed : .notInstalled
    }

    static var modelDirectory: URL {
        PrivatePinyinSettingsStore.supportDirectory
            .appendingPathComponent("WriterModels", isDirectory: true)
            .appendingPathComponent(modelID, isDirectory: true)
    }

    static var modelURL: URL {
        modelDirectory.appendingPathComponent(modelFilename, isDirectory: false)
    }

    var isInstalled: Bool {
        state == .installed
    }

    func refreshState() {
        guard downloadTask == nil else { return }
        state = Self.quickInstalledCheck() ? .installed : .notInstalled
    }

    func startDownload() {
        guard downloadTask == nil else { return }
        state = .downloading(0)
        let task = session.downloadTask(with: Self.downloadURL)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = Self.quickInstalledCheck() ? .installed : .notInstalled
    }

    func removeModel() throws {
        cancelDownload()
        if FileManager.default.fileExists(atPath: Self.modelDirectory.path) {
            try FileManager.default.removeItem(at: Self.modelDirectory)
        }
        state = .notInstalled
        PrivatePinyinAIHelperClient.shared.shutdown()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : Self.expectedSize
        let percent = min(99, max(0, Int(totalBytesWritten * 100 / expected)))
        state = .downloading(percent)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        state = .verifying
        do {
            try Self.verifyDownloadedModel(at: location)
            try FileManager.default.createDirectory(
                at: Self.modelDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let stagedURL = Self.modelDirectory.appendingPathComponent(
                ".\(Self.modelFilename).incoming",
                isDirectory: false
            )
            try? FileManager.default.removeItem(at: stagedURL)
            try FileManager.default.moveItem(at: location, to: stagedURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stagedURL.path
            )
            if FileManager.default.fileExists(atPath: Self.modelURL.path) {
                _ = try FileManager.default.replaceItemAt(Self.modelURL, withItemAt: stagedURL)
            } else {
                try FileManager.default.moveItem(at: stagedURL, to: Self.modelURL)
            }
            self.downloadTask = nil
            state = .installed
        } catch {
            self.downloadTask = nil
            state = .failed("模型校验失败，请重新下载。")
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        downloadTask = nil
        if (error as NSError).code == NSURLErrorCancelled {
            state = Self.quickInstalledCheck() ? .installed : .notInstalled
        } else {
            state = .failed("下载失败，请检查网络后重试。")
        }
    }

    private static func quickInstalledCheck() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value == expectedSize
    }

    private static func verifyDownloadedModel(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == expectedSize else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
