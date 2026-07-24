import Carbon
import Foundation

enum PrivatePinyinInputSourceRegistration {
    // Registration health includes disabled sources. Enabling remains an
    // explicit user action in System Settings.
    static let includeAllInstalledSources = true

    static let requiredSourceIdentifiers: Set<String> = [
        "com.privatepinyin.inputmethod.PrivatePinyin",
        "com.privatepinyin.inputmethod.PrivatePinyin.Mode",
    ]

    enum Result: Equatable {
        case alreadyRegistered
        case registered
        case failed
    }

    static func ensureRegistered(bundleURL: URL, forceRefresh: Bool = false) -> Result {
        if !shouldRegister(
            sourceIdentifiers: installedSourceIdentifiers(),
            forceRefresh: forceRefresh
        ) {
            return .alreadyRegistered
        }

        guard TISRegisterInputSource(bundleURL as CFURL) == noErr else {
            return .failed
        }

        return needsRegistration(sourceIdentifiers: installedSourceIdentifiers())
            ? .failed
            : .registered
    }

    static func needsRegistration(sourceIdentifiers: Set<String>) -> Bool {
        !requiredSourceIdentifiers.isSubset(of: sourceIdentifiers)
    }

    static func shouldRegister(
        sourceIdentifiers: Set<String>,
        forceRefresh: Bool
    ) -> Bool {
        forceRefresh || needsRegistration(sourceIdentifiers: sourceIdentifiers)
    }

    private static func installedSourceIdentifiers() -> Set<String> {
        guard let sourceList = TISCreateInputSourceList(
            nil,
            includeAllInstalledSources
        )?.takeRetainedValue(),
              let sources = sourceList as? [TISInputSource]
        else {
            return []
        }

        return Set(sources.compactMap { source in
            guard let property = TISGetInputSourceProperty(
                source,
                kTISPropertyInputSourceID
            ) else {
                return nil
            }
            return Unmanaged<CFString>
                .fromOpaque(property)
                .takeUnretainedValue() as String
        })
    }
}
