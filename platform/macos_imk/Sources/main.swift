import Cocoa
import InputMethodKit

private let connectionName = "PrivatePinyin_1_Connection"
private let bundleIdentifier = "com.privatepinyin.inputmethod.PrivatePinyin"

private var server: IMKServer?
private var applicationDelegate: PrivatePinyinUIHelperApplicationDelegate?
private let shouldShowOnboarding = CommandLine.arguments.contains("--show-onboarding")
private let shouldShowPreferences = CommandLine.arguments.contains("--show-preferences")
private let shouldRunPostInstallFollowUp = CommandLine.arguments.contains(
    PrivatePinyinPostInstallArguments.followUpFlag
)
private let isUIOnlyHelper = PrivatePinyinLaunchPolicy.isUIOnlyLaunch(
    arguments: CommandLine.arguments
)
private let shouldStartInputMethodServer = PrivatePinyinLaunchPolicy.shouldStartInputMethodServer(
    arguments: CommandLine.arguments,
    bundleURL: Bundle.main.bundleURL
)
private let shouldRestoreInstalledServer = PrivatePinyinLaunchPolicy.shouldRestoreInstalledServer(
    bundleURL: Bundle.main.bundleURL
)
private let isInstalledInputMethodBundle = PrivatePinyinLaunchPolicy.isInstalledInputMethodBundle(
    Bundle.main.bundleURL
)

private final class PrivatePinyinUIHelperApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
application.setActivationPolicy(shouldShowPreferences ? .regular : .accessory)

if isInstalledInputMethodBundle {
    let registrationResult = PrivatePinyinInputSourceRegistration.ensureRegistered(
        bundleURL: Bundle.main.bundleURL
    )
    if registrationResult == .registered {
        writeLaunchDiagnostic("input_source_registration_repaired")
    } else if registrationResult == .failed {
        writeLaunchDiagnostic("input_source_registration_failed")
    }
}

if isUIOnlyHelper || !shouldStartInputMethodServer {
    let delegate = PrivatePinyinUIHelperApplicationDelegate()
    applicationDelegate = delegate
    application.delegate = delegate
} else {
    server = IMKServer(
        name: connectionName,
        bundleIdentifier: bundleIdentifier
    )
}

if shouldRestoreInstalledServer {
    restoreInstalledInputMethodServerIfNeeded()
}

if shouldRunPostInstallFollowUp {
    let installedAt = PrivatePinyinPostInstallArguments.installationDate(
        in: CommandLine.arguments
    )
    DispatchQueue.main.async {
        PrivatePinyinPostInstallCoordinator.shared.start(installedAt: installedAt)
    }
} else if shouldShowOnboarding {
    DispatchQueue.main.async {
        PrivatePinyinOnboardingWindowController.shared.showOnboarding()
    }
} else if shouldShowPreferences {
    DispatchQueue.main.async {
        PrivatePinyinPreferencesWindowController.shared.showPreferences()
    }
} else if shouldStartInputMethodServer {
    PrivatePinyinUpdateController.shared.scheduleAutomaticCheck()
} else {
    writeLaunchDiagnostic("uninstalled_bundle_refused_imk_server")
    DispatchQueue.main.async {
        application.terminate(nil)
    }
}

application.run()

private func restoreInstalledInputMethodServerIfNeeded() {
    let fileManager = FileManager.default
    guard let installedBundleURL = PrivatePinyinLaunchPolicy
        .installedBundleURLs(homeDirectory: fileManager.homeDirectoryForCurrentUser)
        .first(where: { fileManager.fileExists(atPath: $0.path) })
    else {
        writeLaunchDiagnostic("installed_bundle_unavailable")
        return
    }

    let registrationResult = PrivatePinyinInputSourceRegistration.ensureRegistered(
        bundleURL: installedBundleURL,
        forceRefresh: true
    )
    guard registrationResult != .failed else {
        writeLaunchDiagnostic("installed_input_source_registration_failed")
        return
    }

    let normalizedInstalledPath = installedBundleURL.standardizedFileURL
        .resolvingSymlinksInPath().path
    let isAlreadyRunning = NSWorkspace.shared.runningApplications.contains {
        $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path
            == normalizedInstalledPath
    }
    guard !isAlreadyRunning else {
        return
    }

    let executableURL = installedBundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("PrivatePinyin", isDirectory: false)
    guard fileManager.isExecutableFile(atPath: executableURL.path) else {
        writeLaunchDiagnostic("installed_executable_unavailable")
        return
    }

    let process = Process()
    process.executableURL = executableURL
    do {
        try process.run()
        writeLaunchDiagnostic("installed_server_restored")
    } catch {
        writeLaunchDiagnostic("installed_server_restore_failed")
    }
}

private func writeLaunchDiagnostic(_ code: String) {
    guard let data = "PrivatePinyin launch code=\(code)\n".data(using: .utf8) else {
        return
    }
    FileHandle.standardError.write(data)
}
