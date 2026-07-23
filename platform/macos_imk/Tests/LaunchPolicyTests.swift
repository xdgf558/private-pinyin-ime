import Foundation

@main
enum LaunchPolicyTests {
    static func main() {
        let homeDirectory = URL(fileURLWithPath: "/Users/tester")
        let systemInstall = URL(fileURLWithPath: "/Library/Input Methods/PrivatePinyin.app")
        let userInstall = URL(
            fileURLWithPath: "/Users/tester/Library/Input Methods/PrivatePinyin.app"
        )
        let developmentBuild = URL(fileURLWithPath: "/workspace/dist/macos_imk/PrivatePinyin.app")
        let misleadingSibling = URL(
            fileURLWithPath: "/Library/Input Methods Backup/PrivatePinyin.app"
        )

        require(
            PrivatePinyinLaunchPolicy.isInstalledInputMethodBundle(
                systemInstall,
                homeDirectory: homeDirectory
            ),
            "system-wide input method install is trusted"
        )
        require(
            PrivatePinyinLaunchPolicy.isInstalledInputMethodBundle(
                userInstall,
                homeDirectory: homeDirectory
            ),
            "per-user input method install is trusted"
        )
        require(
            !PrivatePinyinLaunchPolicy.isInstalledInputMethodBundle(
                developmentBuild,
                homeDirectory: homeDirectory
            ),
            "development build is not an installed input method"
        )
        require(
            !PrivatePinyinLaunchPolicy.isInstalledInputMethodBundle(
                misleadingSibling,
                homeDirectory: homeDirectory
            ),
            "similarly named sibling directory is not trusted"
        )
        require(
            PrivatePinyinLaunchPolicy.shouldStartInputMethodServer(
                arguments: ["PrivatePinyin"],
                bundleURL: systemInstall,
                homeDirectory: homeDirectory
            ),
            "installed background launch starts the IMK server"
        )
        require(
            !PrivatePinyinLaunchPolicy.shouldStartInputMethodServer(
                arguments: ["PrivatePinyin", "--show-preferences"],
                bundleURL: systemInstall,
                homeDirectory: homeDirectory
            ),
            "installed preferences launch remains UI-only"
        )
        require(
            !PrivatePinyinLaunchPolicy.shouldStartInputMethodServer(
                arguments: ["PrivatePinyin"],
                bundleURL: developmentBuild,
                homeDirectory: homeDirectory
            ),
            "uninstalled background launch cannot start the IMK server"
        )
        require(
            PrivatePinyinLaunchPolicy.shouldRestoreInstalledServer(
                bundleURL: developmentBuild,
                homeDirectory: homeDirectory
            ),
            "development launch restores the installed server"
        )

        print("macOS launch policy tests passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
