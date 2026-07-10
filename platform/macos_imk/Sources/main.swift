import Cocoa
import InputMethodKit

private let connectionName = "PrivatePinyin_1_Connection"
private let bundleIdentifier = "com.privatepinyin.inputmethod.PrivatePinyin"

private var server: IMKServer?
private let shouldShowOnboarding = CommandLine.arguments.contains("--show-onboarding")
private let shouldShowPreferences = CommandLine.arguments.contains("--show-preferences")

let application = NSApplication.shared
application.setActivationPolicy(shouldShowPreferences ? .regular : .accessory)

if !shouldShowPreferences {
    server = IMKServer(
        name: connectionName,
        bundleIdentifier: bundleIdentifier
    )
}

if shouldShowOnboarding {
    DispatchQueue.main.async {
        PrivatePinyinOnboardingWindowController.shared.showOnboarding()
    }
} else if shouldShowPreferences {
    DispatchQueue.main.async {
        PrivatePinyinPreferencesWindowController.shared.showPreferences()
    }
}

application.run()
