import Foundation

private final class FakeCommandRunner: PrivatePinyinCommandRunning {
    var signatureResult = PrivatePinyinCommandResult(
        terminationStatus: 0,
        output: """
        Package "PrivatePinyin.pkg":
           Status: signed by a developer certificate issued by Apple for distribution
           Certificate Chain:
            1. Developer ID Installer: HAO YE (Y35K7AQ974)
        """
    )
    var gatekeeperResult = PrivatePinyinCommandResult(
        terminationStatus: 0,
        output: """
        PrivatePinyin.pkg: accepted
        source=Notarized Developer ID
        origin=Developer ID Installer: HAO YE (Y35K7AQ974)
        """
    )
    private(set) var calls: [String] = []

    func run(executableURL: URL, arguments: [String]) throws -> PrivatePinyinCommandResult {
        calls.append(executableURL.lastPathComponent)
        switch executableURL.lastPathComponent {
        case "pkgutil":
            return signatureResult
        case "spctl":
            return gatekeeperResult
        default:
            throw CocoaError(.executableNotLoadable)
        }
    }
}

@main
enum UpdatePackageVerifierTests {
    private static let abcSHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    static func main() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("private-pinyin-update-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let packageURL = temporaryDirectory.appendingPathComponent("PrivatePinyin.pkg")
        try Data("abc".utf8).write(to: packageURL)

        let validRunner = FakeCommandRunner()
        try PrivatePinyinPackageVerifier(
            expectedTeamIdentifier: "Y35K7AQ974",
            commandRunner: validRunner
        ).verify(packageURL: packageURL, expectedSize: 3, expectedSHA256: abcSHA256)
        require(validRunner.calls == ["pkgutil", "spctl"], "valid package runs both system checks")

        let sizeRunner = FakeCommandRunner()
        requireThrows(
            verifier: PrivatePinyinPackageVerifier(
                expectedTeamIdentifier: "Y35K7AQ974",
                commandRunner: sizeRunner
            ),
            packageURL: packageURL,
            expectedSize: 4,
            expectedSHA256: abcSHA256,
            expectedError: .invalidFileSize
        )
        require(sizeRunner.calls.isEmpty, "size mismatch stops before system commands")

        let digestRunner = FakeCommandRunner()
        requireThrows(
            verifier: PrivatePinyinPackageVerifier(
                expectedTeamIdentifier: "Y35K7AQ974",
                commandRunner: digestRunner
            ),
            packageURL: packageURL,
            expectedSize: 3,
            expectedSHA256: String(repeating: "0", count: 64),
            expectedError: .invalidDigest
        )
        require(digestRunner.calls.isEmpty, "digest mismatch stops before system commands")

        let signatureRunner = FakeCommandRunner()
        signatureRunner.signatureResult = PrivatePinyinCommandResult(
            terminationStatus: 0,
            output: "Status: invalid signature"
        )
        requireThrows(
            verifier: PrivatePinyinPackageVerifier(
                expectedTeamIdentifier: "Y35K7AQ974",
                commandRunner: signatureRunner
            ),
            packageURL: packageURL,
            expectedSize: 3,
            expectedSHA256: abcSHA256,
            expectedError: .invalidInstallerSignature
        )

        let unrelatedTeamRunner = FakeCommandRunner()
        unrelatedTeamRunner.signatureResult = PrivatePinyinCommandResult(
            terminationStatus: 0,
            output: """
            Status: signed by a developer certificate issued by Apple for distribution
            1. Developer ID Installer: OTHER DEVELOPER (AAAAAAAAAA)
            Package metadata: Y35K7AQ974
            """
        )
        requireThrows(
            verifier: PrivatePinyinPackageVerifier(
                expectedTeamIdentifier: "Y35K7AQ974",
                commandRunner: unrelatedTeamRunner
            ),
            packageURL: packageURL,
            expectedSize: 3,
            expectedSHA256: abcSHA256,
            expectedError: .invalidInstallerSignature
        )

        let notarizationRunner = FakeCommandRunner()
        notarizationRunner.gatekeeperResult = PrivatePinyinCommandResult(
            terminationStatus: 3,
            output: "PrivatePinyin.pkg: rejected"
        )
        requireThrows(
            verifier: PrivatePinyinPackageVerifier(
                expectedTeamIdentifier: "Y35K7AQ974",
                commandRunner: notarizationRunner
            ),
            packageURL: packageURL,
            expectedSize: 3,
            expectedSHA256: abcSHA256,
            expectedError: .notarizationRejected
        )

        requireThrows(
            verifier: PrivatePinyinPackageVerifier(
                expectedTeamIdentifier: "INVALID",
                commandRunner: FakeCommandRunner()
            ),
            packageURL: packageURL,
            expectedSize: 3,
            expectedSHA256: abcSHA256,
            expectedError: .invalidTeamIdentifier
        )

        print("UPDATE-02 package verifier tests passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }

    private static func requireThrows(
        verifier: PrivatePinyinPackageVerifier,
        packageURL: URL,
        expectedSize: Int64,
        expectedSHA256: String,
        expectedError: PrivatePinyinPackageVerificationError
    ) {
        do {
            try verifier.verify(
                packageURL: packageURL,
                expectedSize: expectedSize,
                expectedSHA256: expectedSHA256
            )
            fatalError("expected verification failure: \(expectedError)")
        } catch let error as PrivatePinyinPackageVerificationError {
            require(error == expectedError, "unexpected verification failure: \(error)")
        } catch {
            fatalError("unexpected error type: \(error)")
        }
    }
}
