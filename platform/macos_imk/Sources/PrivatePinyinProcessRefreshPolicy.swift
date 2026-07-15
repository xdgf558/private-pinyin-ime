import Foundation

struct PrivatePinyinProcessSnapshot: Equatable {
    let processIdentifier: Int32
    let launchDate: Date?
}

enum PrivatePinyinPostInstallArguments {
    static let followUpFlag = "--post-install-follow-up"
    static let installedAtFlag = "--installed-at"

    static func installationDate(
        in arguments: [String],
        now: Date = Date()
    ) -> Date? {
        guard
            let flagIndex = arguments.firstIndex(of: installedAtFlag),
            arguments.indices.contains(flagIndex + 1),
            let epoch = TimeInterval(arguments[flagIndex + 1]),
            epoch.isFinite
        else {
            return nil
        }

        let date = Date(timeIntervalSince1970: epoch)
        let earliestAcceptedDate = now.addingTimeInterval(-30 * 60)
        let latestAcceptedDate = now.addingTimeInterval(60)
        guard date >= earliestAcceptedDate, date <= latestAcceptedDate else {
            return nil
        }
        return date
    }
}

enum PrivatePinyinProcessRefreshPolicy {
    static func staleProcessIdentifiers(
        in snapshots: [PrivatePinyinProcessSnapshot],
        currentProcessIdentifier: Int32,
        installedAt: Date
    ) -> Set<Int32> {
        return Set(snapshots.compactMap { snapshot in
            guard
                snapshot.processIdentifier > 0,
                snapshot.processIdentifier != currentProcessIdentifier,
                let launchDate = snapshot.launchDate,
                // Preserve every process launched at or after the handoff
                // boundary. A same-second false negative is safer than
                // terminating a newly launched input-method process.
                launchDate < installedAt
            else {
                return nil
            }
            return snapshot.processIdentifier
        })
    }

    static func eligibleProcessIdentifiers(
        requestedProcessIdentifiers: Set<Int32>,
        currentSnapshots: [PrivatePinyinProcessSnapshot],
        currentProcessIdentifier: Int32,
        installedAt: Date
    ) -> Set<Int32> {
        staleProcessIdentifiers(
            in: currentSnapshots,
            currentProcessIdentifier: currentProcessIdentifier,
            installedAt: installedAt
        ).intersection(requestedProcessIdentifiers)
    }
}
