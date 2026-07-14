import Cocoa
import Foundation

enum PrivatePinyinUpdateState: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(PrivatePinyinValidatedUpdate)
    case systemUpgradeRequired(PrivatePinyinValidatedUpdate)
    case failed
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
    private let currentVersion: String
    private let currentBuild: Int
    private let currentSystemVersion: String
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
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
        case .checking:
            return "正在检查更新..."
        default:
            return "检查更新..."
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
        }
    }

    func scheduleAutomaticCheck(force: Bool = false) {
        guard automaticChecksEffectivelyEnabled, activeTask == nil else {
            return
        }
        if !force,
           let previous = defaults.object(forKey: DefaultsKey.lastAutomaticAttempt) as? Date,
           Date().timeIntervalSince(previous) < Self.automaticCheckInterval
        {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.automaticChecksEffectivelyEnabled, self.activeTask == nil else {
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
        case .checking:
            break
        default:
            checkForUpdates(presentingWindow: presentingWindow)
        }
    }

    func checkForUpdates(presentingWindow: NSWindow? = nil) {
        guard activeTask == nil else {
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
        alert.informativeText = "\(update.manifest.title)\n\n\(update.formattedReleaseNotes)"
        alert.addButton(withTitle: supported ? "前往更新页面" : "查看更新说明")
        alert.addButton(withTitle: "稍后")
        present(alert: alert, presentingWindow: presentingWindow) { response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            NSWorkspace.shared.open(update.releasePageURL)
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
