import Cocoa
import Foundation

enum PrivatePinyinUpdateState: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(PrivatePinyinValidatedUpdate)
    case systemUpgradeRequired(PrivatePinyinValidatedUpdate)
    case downloading(PrivatePinyinValidatedUpdate, progress: Int)
    case verifying(PrivatePinyinValidatedUpdate)
    case readyToInstall(PrivatePinyinValidatedUpdate, packageURL: URL, installerOpened: Bool)
    case packageFailed(PrivatePinyinValidatedUpdate, PrivatePinyinPackageFailure)
    case failed
}

enum PrivatePinyinPackageFailure: Equatable {
    case download
    case storage
    case size
    case digest
    case signature
    case notarization
    case verificationUnavailable
    case installerUnavailable
}

final class PrivatePinyinUpdateController: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = PrivatePinyinUpdateController()

    private enum DefaultsKey {
        static let automaticChecksEnabled = "PrivatePinyinAutomaticUpdateChecksEnabled"
        static let automaticChecksConfigured = "PrivatePinyinAutomaticUpdateChecksConfigured"
        static let lastAutomaticAttempt = "PrivatePinyinLastAutomaticUpdateAttempt"
        static let lastSuccessfulCheck = "PrivatePinyinLastSuccessfulUpdateCheck"
        static let cachedManifest = "PrivatePinyinCachedUpdateManifest"
    }

    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let maximumManifestBytes = 128 * 1024

    private let defaults = UserDefaults.standard
    private let endpointURL: URL?
    private let allowedHost: String
    private let expectedInstallerTeamIdentifier: String
    private let currentVersion: String
    private let currentBuild: Int
    private let currentSystemVersion: String
    private let verificationQueue = DispatchQueue(
        label: "PrivatePinyin.UpdateVerification",
        qos: .userInitiated
    )
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()
    private var activeTask: URLSessionDataTask?
    private var activeCheckID: UUID?
    private var receivedResponse: URLResponse?
    private var receivedData = Data()
    private var responseExceededLimit = false
    private var userInitiatedCheck = false
    private weak var presentingWindow: NSWindow?
    private var packageDownloader: PrivatePinyinPackageDownloader?
    private var activePackageOperationID: UUID?

    private(set) var state: PrivatePinyinUpdateState = .idle {
        didSet {
            NotificationCenter.default.post(name: .privatePinyinUpdateStateChanged, object: self)
        }
    }

    private override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let endpoint = info["PrivatePinyinUpdateManifestURL"] as? String
        endpointURL = endpoint.flatMap(URL.init(string:))
        allowedHost = (info["PrivatePinyinUpdateAllowedHost"] as? String ?? "").lowercased()
        expectedInstallerTeamIdentifier = info["PrivatePinyinUpdateExpectedInstallerTeamID"] as? String ?? ""
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "0"
        currentBuild = Int(info["CFBundleVersion"] as? String ?? "0") ?? 0
        let system = ProcessInfo.processInfo.operatingSystemVersion
        currentSystemVersion = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        super.init()
        restoreCachedState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged(_:)),
            name: .privatePinyinSettingsChanged,
            object: nil
        )
    }

    var automaticChecksEnabled: Bool {
        if !defaults.bool(forKey: DefaultsKey.automaticChecksConfigured) {
            return false
        }
        return defaults.bool(forKey: DefaultsKey.automaticChecksEnabled)
    }

    var automaticChecksEffectivelyEnabled: Bool {
        automaticChecksEnabled && !PrivatePinyinSettingsStore.isStrictPrivacyModeEnabled()
    }

    var menuTitle: String {
        switch state {
        case let .updateAvailable(update):
            return "发现新版本 \(update.manifest.version)..."
        case let .systemUpgradeRequired(update):
            return "新版本需要 macOS \(update.manifest.minimumMacOSVersion)"
        case let .downloading(_, progress):
            return "取消更新下载（\(progress)%）"
        case .verifying:
            return "正在验证更新..."
        case let .readyToInstall(_, _, installerOpened):
            return installerOpened ? "重新打开系统安装器..." : "打开系统安装器..."
        case .packageFailed:
            return "更新验证失败，重试..."
        case .checking:
            return "正在检查更新..."
        default:
            return "检查更新..."
        }
    }

    var isMenuActionEnabled: Bool {
        switch state {
        case .checking, .verifying:
            return false
        default:
            return true
        }
    }

    private var blocksVersionCheck: Bool {
        switch state {
        case .downloading, .verifying, .readyToInstall:
            return true
        default:
            return false
        }
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: DefaultsKey.automaticChecksConfigured)
        defaults.set(enabled, forKey: DefaultsKey.automaticChecksEnabled)
        if enabled {
            scheduleAutomaticCheck(force: true)
        } else {
            cancelBackgroundCheckIfNeeded()
        }
        NotificationCenter.default.post(name: .privatePinyinUpdateStateChanged, object: self)
    }

    func applyCurrentPrivacyPolicy() {
        if PrivatePinyinSettingsStore.isStrictPrivacyModeEnabled() {
            cancelBackgroundCheckIfNeeded()
            cancelPackageDownloadIfNeeded()
        }
    }

    func scheduleAutomaticCheck(force: Bool = false) {
        guard automaticChecksEffectivelyEnabled,
              activeTask == nil,
              activePackageOperationID == nil,
              !blocksVersionCheck
        else {
            return
        }
        if !force,
           let previous = defaults.object(forKey: DefaultsKey.lastAutomaticAttempt) as? Date,
           Date().timeIntervalSince(previous) < Self.automaticCheckInterval
        {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self,
                  self.automaticChecksEffectivelyEnabled,
                  self.activeTask == nil,
                  self.activePackageOperationID == nil,
                  !self.blocksVersionCheck
            else {
                return
            }
            if !force,
               let previous = self.defaults.object(forKey: DefaultsKey.lastAutomaticAttempt) as? Date,
               Date().timeIntervalSince(previous) < Self.automaticCheckInterval
            {
                return
            }
            self.defaults.set(Date(), forKey: DefaultsKey.lastAutomaticAttempt)
            self.startCheck(userInitiated: false, presentingWindow: nil)
        }
    }

    func checkOrPresentUpdate(presentingWindow: NSWindow? = nil) {
        switch state {
        case let .updateAvailable(update), let .systemUpgradeRequired(update):
            present(update: update, presentingWindow: presentingWindow)
        case .downloading:
            cancelPackageDownloadIfNeeded()
        case let .readyToInstall(update, packageURL, _):
            presentInstallerHandoff(
                update: update,
                packageURL: packageURL,
                presentingWindow: presentingWindow
            )
        case let .packageFailed(update, _):
            present(update: update, presentingWindow: presentingWindow)
        case .checking, .verifying:
            break
        default:
            checkForUpdates(presentingWindow: presentingWindow)
        }
    }

    func checkForUpdates(presentingWindow: NSWindow? = nil) {
        guard activeTask == nil,
              activePackageOperationID == nil,
              !blocksVersionCheck
        else {
            return
        }
        if PrivatePinyinSettingsStore.isStrictPrivacyModeEnabled(),
           !confirmStrictPrivacyOverride(presentingWindow: presentingWindow)
        {
            return
        }
        startCheck(userInitiated: true, presentingWindow: presentingWindow)
    }

    private func startCheck(userInitiated: Bool, presentingWindow: NSWindow?) {
        guard let endpointURL, isAllowedEndpoint(endpointURL) else {
            finish(with: .failed, userInitiated: userInitiated, presentingWindow: presentingWindow)
            return
        }

        self.userInitiatedCheck = userInitiated
        self.presentingWindow = presentingWindow
        let checkID = UUID()
        activeCheckID = checkID
        receivedResponse = nil
        receivedData.removeAll(keepingCapacity: true)
        responseExceededLimit = false
        state = .checking

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)
        activeTask = task
        task.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, checkID: UUID) {
        guard activeCheckID == checkID else {
            return
        }
        let wasUserInitiated = userInitiatedCheck
        let window = presentingWindow
        activeTask = nil
        activeCheckID = nil
        receivedResponse = nil
        receivedData.removeAll(keepingCapacity: true)
        responseExceededLimit = false
        userInitiatedCheck = false
        presentingWindow = nil

        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let responseURL = http.url,
              isAllowedEndpoint(responseURL),
              let data,
              !data.isEmpty,
              data.count <= Self.maximumManifestBytes,
              let decoded = try? JSONDecoder().decode(PrivatePinyinUpdateManifest.self, from: data),
              let update = try? decoded.validated(allowedHost: allowedHost)
        else {
            finish(with: .failed, userInitiated: wasUserInitiated, presentingWindow: window)
            return
        }

        defaults.set(Date(), forKey: DefaultsKey.lastSuccessfulCheck)
        defaults.set(data, forKey: DefaultsKey.cachedManifest)
        let nextState = evaluatedState(for: update, checkedAt: Date())
        finish(with: nextState, userInitiated: wasUserInitiated, presentingWindow: window)
    }

    private func evaluatedState(
        for update: PrivatePinyinValidatedUpdate,
        checkedAt: Date
    ) -> PrivatePinyinUpdateState {
        guard update.isNewer(than: currentVersion, build: currentBuild) else {
            return .upToDate(checkedAt: checkedAt)
        }
        if update.supports(systemVersion: currentSystemVersion) {
            return .updateAvailable(update)
        }
        return .systemUpgradeRequired(update)
    }

    private func restoreCachedState() {
        guard let data = defaults.data(forKey: DefaultsKey.cachedManifest),
              let manifest = try? JSONDecoder().decode(PrivatePinyinUpdateManifest.self, from: data),
              let update = try? manifest.validated(allowedHost: allowedHost)
        else {
            return
        }
        let checkedAt = defaults.object(forKey: DefaultsKey.lastSuccessfulCheck) as? Date ?? .distantPast
        state = evaluatedState(for: update, checkedAt: checkedAt)
    }

    @objc private func settingsChanged(_ notification: Notification) {
        applyCurrentPrivacyPolicy()
    }

    private func cancelBackgroundCheckIfNeeded() {
        guard activeTask != nil, !userInitiatedCheck else {
            return
        }
        activeCheckID = nil
        activeTask?.cancel()
        activeTask = nil
        presentingWindow = nil
        receivedResponse = nil
        receivedData.removeAll(keepingCapacity: true)
        responseExceededLimit = false
        state = .idle
        restoreCachedState()
    }

    private func cancelPackageDownloadIfNeeded() {
        guard case let .downloading(update, _) = state else {
            return
        }
        activePackageOperationID = nil
        packageDownloader?.cancel()
        packageDownloader = nil
        state = .updateAvailable(update)
    }

    private func finish(
        with newState: PrivatePinyinUpdateState,
        userInitiated: Bool,
        presentingWindow: NSWindow?
    ) {
        state = newState
        guard userInitiated else {
            return
        }

        switch newState {
        case let .updateAvailable(update), let .systemUpgradeRequired(update):
            present(update: update, presentingWindow: presentingWindow)
        case .upToDate:
            presentAlert(
                title: "已经是最新版本",
                detail: "当前安装的是猫栈拼音 \(currentVersion)。",
                presentingWindow: presentingWindow
            )
        case .failed:
            presentAlert(
                title: "暂时无法检查更新",
                detail: "输入功能不受影响。请检查网络后稍后重试。",
                presentingWindow: presentingWindow
            )
        default:
            break
        }
    }

    private func present(update: PrivatePinyinValidatedUpdate, presentingWindow: NSWindow?) {
        let supported = update.supports(systemVersion: currentSystemVersion)
        let alert = NSAlert()
        alert.messageText = supported
            ? "猫栈拼音 \(update.manifest.version) 可以更新"
            : "新版本需要 macOS \(update.manifest.minimumMacOSVersion)"
        let packageSize = ByteCountFormatter.string(
            fromByteCount: update.manifest.packageSizeBytes,
            countStyle: .file
        )
        alert.informativeText = supported
            ? "\(update.manifest.title)\n\n\(update.formattedReleaseNotes)\n\n下载大小：\(packageSize)。下载后会在本机验证 SHA-256、Developer ID Installer 签名和 Apple 公证，再交给系统安装器。"
            : "\(update.manifest.title)\n\n\(update.formattedReleaseNotes)"
        alert.addButton(withTitle: supported ? "下载并验证" : "查看更新说明")
        if supported {
            alert.addButton(withTitle: "查看更新说明")
        }
        alert.addButton(withTitle: "稍后")
        present(alert: alert, presentingWindow: presentingWindow) { response in
            if supported, response == .alertFirstButtonReturn {
                self.beginPackageDownload(update: update, presentingWindow: presentingWindow)
            } else if (!supported && response == .alertFirstButtonReturn) ||
                (supported && response == .alertSecondButtonReturn)
            {
                NSWorkspace.shared.open(update.releasePageURL)
            }
        }
    }

    private func beginPackageDownload(
        update: PrivatePinyinValidatedUpdate,
        presentingWindow: NSWindow?
    ) {
        guard activeTask == nil, activePackageOperationID == nil else {
            return
        }
        let operationID = UUID()
        activePackageOperationID = operationID
        state = .downloading(update, progress: 0)

        let destinationFileName = "PrivatePinyin-\(update.manifest.version)-\(update.manifest.build).pkg"
        let downloader = PrivatePinyinPackageDownloader(
            packageURL: update.packageURL,
            allowedHost: allowedHost,
            expectedSize: update.manifest.packageSizeBytes,
            destinationFileName: destinationFileName,
            progressHandler: { [weak self] progress in
                guard let self, self.activePackageOperationID == operationID else {
                    return
                }
                self.state = .downloading(update, progress: progress)
            },
            completionHandler: { [weak self] result in
                guard let self, self.activePackageOperationID == operationID else {
                    return
                }
                self.packageDownloader = nil
                switch result {
                case let .success(packageURL):
                    self.verifyPackage(
                        update: update,
                        packageURL: packageURL,
                        operationID: operationID,
                        purpose: .prepare,
                        presentingWindow: presentingWindow
                    )
                case let .failure(error):
                    self.activePackageOperationID = nil
                    if error == .cancelled {
                        self.state = .updateAvailable(update)
                    } else {
                        let failure = Self.packageFailure(for: error)
                        self.state = .packageFailed(update, failure)
                        self.presentPackageFailure(
                            update: update,
                            failure: failure,
                            presentingWindow: presentingWindow
                        )
                    }
                }
            }
        )
        packageDownloader = downloader
        downloader.start()
    }

    private enum VerificationPurpose {
        case prepare
        case installerHandoff
    }

    private func verifyPackage(
        update: PrivatePinyinValidatedUpdate,
        packageURL: URL,
        operationID: UUID,
        purpose: VerificationPurpose,
        presentingWindow: NSWindow?
    ) {
        state = .verifying(update)
        let teamIdentifier = expectedInstallerTeamIdentifier
        let expectedSize = update.manifest.packageSizeBytes
        let expectedDigest = update.manifest.packageSHA256

        verificationQueue.async { [weak self] in
            let failure: PrivatePinyinPackageVerificationError?
            do {
                try PrivatePinyinPackageVerifier(
                    expectedTeamIdentifier: teamIdentifier
                ).verify(
                    packageURL: packageURL,
                    expectedSize: expectedSize,
                    expectedSHA256: expectedDigest
                )
                failure = nil
            } catch let error as PrivatePinyinPackageVerificationError {
                failure = error
            } catch {
                failure = .commandFailed
            }

            DispatchQueue.main.async {
                guard let self, self.activePackageOperationID == operationID else {
                    return
                }
                if let failure {
                    self.activePackageOperationID = nil
                    try? FileManager.default.removeItem(at: packageURL)
                    let packageFailure = Self.packageFailure(for: failure)
                    self.state = .packageFailed(update, packageFailure)
                    self.presentPackageFailure(
                        update: update,
                        failure: packageFailure,
                        presentingWindow: presentingWindow
                    )
                    return
                }

                self.activePackageOperationID = nil
                switch purpose {
                case .prepare:
                    self.state = .readyToInstall(update, packageURL: packageURL, installerOpened: false)
                    self.presentInstallerHandoff(
                        update: update,
                        packageURL: packageURL,
                        presentingWindow: presentingWindow
                    )
                case .installerHandoff:
                    self.openSystemInstaller(
                        update: update,
                        packageURL: packageURL,
                        presentingWindow: presentingWindow
                    )
                }
            }
        }
    }

    private func presentInstallerHandoff(
        update: PrivatePinyinValidatedUpdate,
        packageURL: URL,
        presentingWindow: NSWindow?
    ) {
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            state = .packageFailed(update, .storage)
            presentPackageFailure(update: update, failure: .storage, presentingWindow: presentingWindow)
            return
        }

        let alert = NSAlert()
        alert.messageText = "更新包已通过安全验证"
        alert.informativeText = "猫栈拼音 \(update.manifest.version) 已通过文件大小、SHA-256、Developer ID Installer 签名和 Apple 公证检查。下一步将打开 macOS 系统安装器，由你确认并输入系统密码。"
        alert.addButton(withTitle: "打开系统安装器")
        alert.addButton(withTitle: "稍后")
        present(alert: alert, presentingWindow: presentingWindow) { response in
            guard response == .alertFirstButtonReturn,
                  self.activePackageOperationID == nil
            else {
                return
            }
            let operationID = UUID()
            self.activePackageOperationID = operationID
            self.verifyPackage(
                update: update,
                packageURL: packageURL,
                operationID: operationID,
                purpose: .installerHandoff,
                presentingWindow: presentingWindow
            )
        }
    }

    private func openSystemInstaller(
        update: PrivatePinyinValidatedUpdate,
        packageURL: URL,
        presentingWindow: NSWindow?
    ) {
        let installerURL = URL(fileURLWithPath: "/System/Library/CoreServices/Installer.app")
        guard FileManager.default.fileExists(atPath: installerURL.path) else {
            state = .packageFailed(update, .installerUnavailable)
            presentPackageFailure(
                update: update,
                failure: .installerUnavailable,
                presentingWindow: presentingWindow
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [packageURL],
            withApplicationAt: installerURL,
            configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if error == nil {
                    self.state = .readyToInstall(update, packageURL: packageURL, installerOpened: true)
                } else {
                    self.state = .packageFailed(update, .installerUnavailable)
                    self.presentPackageFailure(
                        update: update,
                        failure: .installerUnavailable,
                        presentingWindow: presentingWindow
                    )
                }
            }
        }
    }

    private func presentPackageFailure(
        update: PrivatePinyinValidatedUpdate,
        failure: PrivatePinyinPackageFailure,
        presentingWindow: NSWindow?
    ) {
        let alert = NSAlert()
        alert.messageText = "无法安全安装这次更新"
        alert.informativeText = Self.packageFailureDetail(failure)
        alert.addButton(withTitle: "重试下载")
        alert.addButton(withTitle: "查看更新说明")
        alert.addButton(withTitle: "稍后")
        present(alert: alert, presentingWindow: presentingWindow) { response in
            if response == .alertFirstButtonReturn {
                self.beginPackageDownload(update: update, presentingWindow: presentingWindow)
            } else if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(update.releasePageURL)
            }
        }
    }

    private static func packageFailure(
        for error: PrivatePinyinPackageDownloadError
    ) -> PrivatePinyinPackageFailure {
        switch error {
        case .cancelled:
            return .download
        case .invalidResponse, .networkFailure:
            return .download
        case .invalidSize:
            return .size
        case .storageFailure:
            return .storage
        }
    }

    private static func packageFailure(
        for error: PrivatePinyinPackageVerificationError
    ) -> PrivatePinyinPackageFailure {
        switch error {
        case .invalidFile:
            return .storage
        case .invalidFileSize:
            return .size
        case .invalidDigest:
            return .digest
        case .invalidInstallerSignature, .invalidTeamIdentifier:
            return .signature
        case .notarizationRejected:
            return .notarization
        case .commandFailed:
            return .verificationUnavailable
        }
    }

    static func packageFailureSummary(_ failure: PrivatePinyinPackageFailure) -> String {
        switch failure {
        case .download:
            return "下载未完成或服务器响应无效，未进入安装流程。"
        case .storage:
            return "无法安全保存或读取更新包，未进入安装流程。"
        case .size:
            return "文件大小与公开清单不一致，更新包已删除。"
        case .digest:
            return "SHA-256 与公开清单不一致，更新包已删除。"
        case .signature:
            return "Developer ID Installer 签名不符合要求，已拒绝安装。"
        case .notarization:
            return "Apple 公证检查未通过，已拒绝安装。"
        case .verificationUnavailable:
            return "系统安全验证暂时不可用，已拒绝安装。"
        case .installerUnavailable:
            return "无法打开 macOS 系统安装器。"
        }
    }

    private static func packageFailureDetail(_ failure: PrivatePinyinPackageFailure) -> String {
        switch failure {
        case .download:
            return "下载没有完成，或服务器返回了不符合清单的文件。输入功能不受影响。"
        case .storage:
            return "无法在本机安全保存或读取更新包。输入功能不受影响。"
        case .size:
            return "更新包的实际大小与公开清单不一致，已拒绝安装并删除文件。"
        case .digest:
            return "更新包的 SHA-256 与公开清单不一致，已拒绝安装并删除文件。"
        case .signature:
            return "更新包不是由猫栈拼音指定的 Developer ID Installer 证书签名，已拒绝安装。"
        case .notarization:
            return "macOS 未确认该更新包通过 Apple 公证，已拒绝安装。"
        case .verificationUnavailable:
            return "本机暂时无法完成系统签名检查，已拒绝安装。"
        case .installerUnavailable:
            return "无法打开 macOS 系统安装器。你可以稍后重试或查看更新说明。"
        }
    }

    private func confirmStrictPrivacyOverride(presentingWindow: NSWindow?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "严格隐私模式已开启"
        alert.informativeText = "手动检查更新只会连接 wwwstationcat.org 获取公开版本清单，不会上传输入内容、用户词库或设备标识。"
        alert.addButton(withTitle: "继续检查")
        alert.addButton(withTitle: "取消")
        return run(alert: alert) == .alertFirstButtonReturn
    }

    private func presentAlert(title: String, detail: String, presentingWindow: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        present(alert: alert, presentingWindow: presentingWindow, completion: nil)
    }

    private func present(
        alert: NSAlert,
        presentingWindow: NSWindow?,
        completion: ((NSApplication.ModalResponse) -> Void)?
    ) {
        NSApp.activate(ignoringOtherApps: true)
        if let presentingWindow, presentingWindow.isVisible {
            alert.beginSheetModal(for: presentingWindow) { response in
                completion?(response)
            }
        } else {
            completion?(alert.runModal())
        }
    }

    private func run(alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private func isAllowedEndpoint(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" &&
            url.host?.lowercased() == allowedHost &&
            url.user == nil &&
            url.password == nil &&
            url.fragment == nil &&
            (url.port == nil || url.port == 443)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, isAllowedEndpoint(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard dataTask === activeTask else {
            completionHandler(.cancel)
            return
        }
        receivedResponse = response
        if response.expectedContentLength > Self.maximumManifestBytes {
            responseExceededLimit = true
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === activeTask, !responseExceededLimit else {
            return
        }
        guard data.count <= Self.maximumManifestBytes - receivedData.count else {
            responseExceededLimit = true
            dataTask.cancel()
            return
        }
        receivedData.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard task === activeTask, let checkID = activeCheckID else {
            return
        }
        let data = responseExceededLimit ? nil : receivedData
        handleResponse(data: data, response: receivedResponse, checkID: checkID)
    }
}

extension Notification.Name {
    static let privatePinyinUpdateStateChanged = Notification.Name("PrivatePinyinUpdateStateChanged")
}
