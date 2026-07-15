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
private let isUIOnlyHelper = shouldShowOnboarding || shouldShowPreferences || shouldRunPostInstallFollowUp

private final class PrivatePinyinUIHelperApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
application.setActivationPolicy(shouldShowPreferences ? .regular : .accessory)

if isUIOnlyHelper {
    let delegate = PrivatePinyinUIHelperApplicationDelegate()
    applicationDelegate = delegate
    application.delegate = delegate
} else {
    server = IMKServer(
        name: connectionName,
        bundleIdentifier: bundleIdentifier
    )
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
} else {
    PrivatePinyinUpdateController.shared.scheduleAutomaticCheck()
}

application.run()
