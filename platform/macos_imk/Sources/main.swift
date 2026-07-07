import Cocoa
import InputMethodKit

private let connectionName = "PrivatePinyin_1_Connection"
private let bundleIdentifier = "com.privatepinyin.inputmethod.PrivatePinyin"

private var server: IMKServer?
private let shouldShowOnboarding = CommandLine.arguments.contains("--show-onboarding")

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

server = IMKServer(
    name: connectionName,
    bundleIdentifier: bundleIdentifier
)

if shouldShowOnboarding {
    DispatchQueue.main.async {
        PrivatePinyinOnboardingWindowController.shared.showOnboarding()
    }
}

application.run()
