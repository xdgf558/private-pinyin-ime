import Foundation

@main
enum InputSourceRegistrationTests {
    static func main() {
        let bundleIdentifier = "com.privatepinyin.inputmethod.PrivatePinyin"
        let modeIdentifier = "\(bundleIdentifier).Mode"

        require(
            PrivatePinyinInputSourceRegistration.includeAllInstalledSources,
            "registration checks include installed sources that are not enabled"
        )
        require(
            PrivatePinyinInputSourceRegistration.needsRegistration(
                sourceIdentifiers: []
            ),
            "an empty registration set requires repair"
        )
        require(
            PrivatePinyinInputSourceRegistration.needsRegistration(
                sourceIdentifiers: [bundleIdentifier]
            ),
            "the input mode identifier is required"
        )
        require(
            !PrivatePinyinInputSourceRegistration.needsRegistration(
                sourceIdentifiers: [bundleIdentifier, modeIdentifier]
            ),
            "the complete installed registration set is healthy even when disabled"
        )
        require(
            !PrivatePinyinInputSourceRegistration.needsRegistration(
                sourceIdentifiers: [
                    bundleIdentifier,
                    modeIdentifier,
                    "com.apple.keylayout.ABC",
                ]
            ),
            "unrelated input sources do not trigger repair"
        )
        require(
            !PrivatePinyinInputSourceRegistration.shouldRegister(
                sourceIdentifiers: [bundleIdentifier, modeIdentifier],
                forceRefresh: false
            ),
            "a healthy registration does not need ordinary repair"
        )
        require(
            PrivatePinyinInputSourceRegistration.shouldRegister(
                sourceIdentifiers: [bundleIdentifier, modeIdentifier],
                forceRefresh: true
            ),
            "recovery refreshes the exact installed bundle path"
        )
        require(
            PrivatePinyinInputSourceRegistration.shouldRegister(
                sourceIdentifiers: [bundleIdentifier],
                forceRefresh: false
            ),
            "a missing input mode triggers ordinary repair"
        )

        print("macOS input source registration tests passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
