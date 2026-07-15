import Foundation

@main
enum ProcessRefreshPolicyTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let installationDate = PrivatePinyinPostInstallArguments.installationDate(
            in: ["PrivatePinyin", "--post-install-follow-up", "--installed-at", "2000000000"],
            now: now
        )
        require(installationDate == now, "valid installer timestamp is accepted")
        require(
            PrivatePinyinPostInstallArguments.installationDate(
                in: ["PrivatePinyin", "--installed-at", "invalid"],
                now: now
            ) == nil,
            "malformed installer timestamp is rejected"
        )
        require(
            PrivatePinyinPostInstallArguments.installationDate(
                in: ["PrivatePinyin", "--installed-at", "1999998000"],
                now: now
            ) == nil,
            "expired installer timestamp is rejected"
        )
        require(
            PrivatePinyinPostInstallArguments.installationDate(
                in: ["PrivatePinyin", "--installed-at", "2000000061"],
                now: now
            ) == nil,
            "future installer timestamp is rejected"
        )

        let snapshots = [
            PrivatePinyinProcessSnapshot(
                processIdentifier: 100,
                launchDate: now.addingTimeInterval(-600)
            ),
            PrivatePinyinProcessSnapshot(
                processIdentifier: 200,
                launchDate: now.addingTimeInterval(-10)
            ),
            PrivatePinyinProcessSnapshot(
                processIdentifier: 300,
                launchDate: now.addingTimeInterval(0.5)
            ),
            PrivatePinyinProcessSnapshot(
                processIdentifier: 400,
                launchDate: now.addingTimeInterval(2)
            ),
            PrivatePinyinProcessSnapshot(
                processIdentifier: 450,
                launchDate: now
            ),
            PrivatePinyinProcessSnapshot(processIdentifier: 500, launchDate: nil),
            PrivatePinyinProcessSnapshot(
                processIdentifier: 0,
                launchDate: now.addingTimeInterval(-100)
            ),
        ]

        let staleIdentifiers = PrivatePinyinProcessRefreshPolicy.staleProcessIdentifiers(
            in: snapshots,
            currentProcessIdentifier: 100,
            installedAt: now
        )
        require(
            staleIdentifiers == Set([200]),
            "same-boundary and post-install same-bundle processes remain running"
        )

        let eligibleIdentifiers = PrivatePinyinProcessRefreshPolicy.eligibleProcessIdentifiers(
            requestedProcessIdentifiers: Set([200, 300, 400, 450, 999]),
            currentSnapshots: snapshots,
            currentProcessIdentifier: 100,
            installedAt: now
        )
        require(
            eligibleIdentifiers == Set([200]),
            "refresh revalidates and intersects the originally detected process set"
        )

        print("UPDATE-03 process refresh policy tests passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
