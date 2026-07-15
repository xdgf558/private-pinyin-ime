import CryptoKit
import Darwin
import Foundation

enum PrivatePinyinPackageVerificationError: Error, Equatable {
    case invalidFile
    case invalidFileSize
    case invalidDigest
    case invalidTeamIdentifier
    case invalidInstallerSignature
    case notarizationRejected
    case commandFailed
}

struct PrivatePinyinCommandResult: Equatable {
    let terminationStatus: Int32
    let output: String
}

private enum PrivatePinyinCommandRunnerError: Error {
    case timedOut
}

protocol PrivatePinyinCommandRunning {
    func run(executableURL: URL, arguments: [String]) throws -> PrivatePinyinCommandResult
}

struct PrivatePinyinSystemCommandRunner: PrivatePinyinCommandRunning {
    private static let commandTimeout: DispatchTimeInterval = .seconds(30)
    private static let terminationGracePeriod: DispatchTimeInterval = .seconds(2)

    func run(executableURL: URL, arguments: [String]) throws -> PrivatePinyinCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        process.environment = [
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }
        try process.run()

        if finished.wait(timeout: .now() + Self.commandTimeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + Self.terminationGracePeriod) == .timedOut,
               process.isRunning
            {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + Self.terminationGracePeriod)
            }
            throw PrivatePinyinCommandRunnerError.timedOut
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        return PrivatePinyinCommandResult(
            terminationStatus: process.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self)
        )
    }
}

struct PrivatePinyinPackageVerifier {
    private static let pkgutilURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
    private static let spctlURL = URL(fileURLWithPath: "/usr/sbin/spctl")
    private static let digestChunkSize = 1024 * 1024

    private let expectedTeamIdentifier: String
    private let commandRunner: any PrivatePinyinCommandRunning

    init(
        expectedTeamIdentifier: String,
        commandRunner: any PrivatePinyinCommandRunning = PrivatePinyinSystemCommandRunner()
    ) {
        self.expectedTeamIdentifier = expectedTeamIdentifier
        self.commandRunner = commandRunner
    }

    func verify(
        packageURL: URL,
        expectedSize: Int64,
        expectedSHA256: String
    ) throws {
        guard isValidTeamIdentifier(expectedTeamIdentifier) else {
            throw PrivatePinyinPackageVerificationError.invalidTeamIdentifier
        }
        guard expectedSize > 0, packageURL.isFileURL else {
            throw PrivatePinyinPackageVerificationError.invalidFile
        }
        let normalizedDigest = expectedSHA256.lowercased()
        guard normalizedDigest.utf8.count == 64,
              normalizedDigest.utf8.allSatisfy({ byte in
                  (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
              })
        else {
            throw PrivatePinyinPackageVerificationError.invalidDigest
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: packageURL.path)
        } catch {
            throw PrivatePinyinPackageVerificationError.invalidFile
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw PrivatePinyinPackageVerificationError.invalidFile
        }
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
              size == expectedSize
        else {
            throw PrivatePinyinPackageVerificationError.invalidFileSize
        }

        let digest: String
        do {
            digest = try sha256(of: packageURL)
        } catch {
            throw PrivatePinyinPackageVerificationError.invalidFile
        }
        guard digest == normalizedDigest else {
            throw PrivatePinyinPackageVerificationError.invalidDigest
        }

        let signature = try run(
            executableURL: Self.pkgutilURL,
            arguments: ["--check-signature", packageURL.path]
        )
        let installerIdentityMatches = signature.output.split(whereSeparator: { $0.isNewline }).contains { line in
            line.contains("Developer ID Installer:") &&
                line.contains("(\(expectedTeamIdentifier))")
        }
        guard signature.terminationStatus == 0,
              signature.output.contains("Status: signed by a developer certificate issued by Apple for distribution"),
              installerIdentityMatches
        else {
            throw PrivatePinyinPackageVerificationError.invalidInstallerSignature
        }

        let gatekeeper = try run(
            executableURL: Self.spctlURL,
            arguments: ["--assess", "--type", "install", "--verbose=4", packageURL.path]
        )
        guard gatekeeper.terminationStatus == 0,
              gatekeeper.output.contains("source=Notarized Developer ID")
        else {
            throw PrivatePinyinPackageVerificationError.notarizationRejected
        }
    }

    private func run(executableURL: URL, arguments: [String]) throws -> PrivatePinyinCommandResult {
        do {
            return try commandRunner.run(executableURL: executableURL, arguments: arguments)
        } catch {
            throw PrivatePinyinPackageVerificationError.commandFailed
        }
    }

    private func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: Self.digestChunkSize), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func isValidTeamIdentifier(_ value: String) -> Bool {
        value.utf8.count == 10 && value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (65 ... 90).contains(byte)
        }
    }
}
