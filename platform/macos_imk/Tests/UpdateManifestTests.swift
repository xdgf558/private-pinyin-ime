import Foundation

@main
enum UpdateManifestTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("expected fixture path")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let manifest = try JSONDecoder().decode(PrivatePinyinUpdateManifest.self, from: data)
        let update = try manifest.validated(allowedHost: "wwwstationcat.org")

        require(update.isNewer(than: "0.1.20", build: 20), "new public version is detected")
        require(!update.isNewer(than: "0.1.21", build: 21), "same build is not an update")
        require(update.isNewer(than: "0.1.21", build: 20), "higher build is detected")
        require(update.supports(systemVersion: "14.0"), "minimum system is supported")
        require(!update.supports(systemVersion: "13.6"), "older system is rejected")
        require(update.formattedReleaseNotes.contains("• 增加固定更新源"), "notes are formatted")

        var insecure = manifest
        insecure = PrivatePinyinUpdateManifest(
            schemaVersion: insecure.schemaVersion,
            channel: insecure.channel,
            version: insecure.version,
            build: insecure.build,
            minimumMacOSVersion: insecure.minimumMacOSVersion,
            publishedAt: insecure.publishedAt,
            title: insecure.title,
            releaseNotes: insecure.releaseNotes,
            releasePageURL: insecure.releasePageURL,
            packageURL: "http://wwwstationcat.org/update.pkg",
            packageSHA256: insecure.packageSHA256,
            packageSizeBytes: insecure.packageSizeBytes
        )
        requireThrows(insecure, expected: .invalidPackageURL)

        let foreignHost = PrivatePinyinUpdateManifest(
            schemaVersion: manifest.schemaVersion,
            channel: manifest.channel,
            version: manifest.version,
            build: manifest.build,
            minimumMacOSVersion: manifest.minimumMacOSVersion,
            publishedAt: manifest.publishedAt,
            title: manifest.title,
            releaseNotes: manifest.releaseNotes,
            releasePageURL: manifest.releasePageURL,
            packageURL: "https://example.com/update.pkg",
            packageSHA256: manifest.packageSHA256,
            packageSizeBytes: manifest.packageSizeBytes
        )
        requireThrows(foreignHost, expected: .invalidPackageURL)

        let invalidDigest = PrivatePinyinUpdateManifest(
            schemaVersion: manifest.schemaVersion,
            channel: manifest.channel,
            version: manifest.version,
            build: manifest.build,
            minimumMacOSVersion: manifest.minimumMacOSVersion,
            publishedAt: manifest.publishedAt,
            title: manifest.title,
            releaseNotes: manifest.releaseNotes,
            releasePageURL: manifest.releasePageURL,
            packageURL: manifest.packageURL,
            packageSHA256: "not-a-sha256",
            packageSizeBytes: manifest.packageSizeBytes
        )
        requireThrows(invalidDigest, expected: .invalidPackageDigest)

        print("UPDATE-01 manifest tests passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }

    private static func requireThrows(
        _ manifest: PrivatePinyinUpdateManifest,
        expected: PrivatePinyinUpdateManifestError
    ) {
        do {
            _ = try manifest.validated(allowedHost: "wwwstationcat.org")
            fatalError("expected validation failure: \(expected)")
        } catch let error as PrivatePinyinUpdateManifestError {
            require(error == expected, "unexpected validation failure: \(error)")
        } catch {
            fatalError("unexpected error type")
        }
    }
}
