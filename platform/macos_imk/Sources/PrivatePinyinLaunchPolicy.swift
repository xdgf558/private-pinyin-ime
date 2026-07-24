import Foundation

enum PrivatePinyinLaunchPolicy {
    static let uiOnlyArguments = [
        "--show-onboarding",
        "--show-preferences",
        "--post-install-follow-up",
    ]

    static func isInstalledInputMethodBundle(
        _ bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let normalizedBundlePath = normalizedPath(bundleURL)
        return installedBundleURLs(homeDirectory: homeDirectory).contains {
            normalizedBundlePath == normalizedPath($0)
        }
    }

    static func installedBundleURLs(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Library/Input Methods/PrivatePinyin.app"),
            homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Input Methods", isDirectory: true)
                .appendingPathComponent("PrivatePinyin.app", isDirectory: true),
        ]
    }

    static func isUIOnlyLaunch(arguments: [String]) -> Bool {
        arguments.contains { uiOnlyArguments.contains($0) }
    }

    static func shouldStartInputMethodServer(
        arguments: [String],
        bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        !isUIOnlyLaunch(arguments: arguments)
            && isInstalledInputMethodBundle(bundleURL, homeDirectory: homeDirectory)
    }

    static func shouldRestoreInstalledServer(
        bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        !isInstalledInputMethodBundle(bundleURL, homeDirectory: homeDirectory)
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
