import Cocoa
import InputMethodKit

private let connectionName = "PrivatePinyin_1_Connection"
private let bundleIdentifier = "com.privatepinyin.inputmethod.PrivatePinyin"

private var server: IMKServer?

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

server = IMKServer(
    name: connectionName,
    bundleIdentifier: bundleIdentifier
)

application.run()
