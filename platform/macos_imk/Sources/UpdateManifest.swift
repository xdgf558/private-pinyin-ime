import Foundation

enum PrivatePinyinUpdateManifestError: Error, Equatable {
    case unsupportedSchema
    case unsupportedChannel
    case invalidVersion
    case invalidBuild
    case invalidSystemVersion
    case invalidPublishedDate
    case invalidTitle
    case invalidReleaseNotes
    case invalidReleasePageURL
    case invalidPackageURL
    case invalidPackageDigest
    case invalidPackageSize
}

struct PrivatePinyinVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 4).contains(parts.count) else {
            return nil
        }

        var parsed: [Int] = []
        parsed.reserveCapacity(parts.count)
        for part in parts {
            guard !part.isEmpty,
                  part.utf8.allSatisfy({ (48 ... 57).contains($0) }),
                  let number = Int(part),
                  number <= 999_999
            else {
                return nil
            }
            parsed.append(number)
        }
        components = parsed
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

struct PrivatePinyinUpdateManifest: Decodable, Equatable {
    let schemaVersion: Int
    let channel: String
    let version: String
    let build: Int
    let minimumMacOSVersion: String
    let publishedAt: String
    let title: String
    let releaseNotes: [String]
    let releasePageURL: String
    let packageURL: String
    let packageSHA256: String
    let packageSizeBytes: Int64

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case channel
        case version
        case build
        case minimumMacOSVersion = "minimum_macos_version"
        case publishedAt = "published_at"
        case title
        case releaseNotes = "release_notes"
        case releasePageURL = "release_page_url"
        case packageURL = "package_url"
        case packageSHA256 = "package_sha256"
        case packageSizeBytes = "package_size_bytes"
    }

    func validated(allowedHost: String) throws -> PrivatePinyinValidatedUpdate {
        guard schemaVersion == 1 else {
            throw PrivatePinyinUpdateManifestError.unsupportedSchema
        }
        guard channel == "stable" else {
            throw PrivatePinyinUpdateManifestError.unsupportedChannel
        }
        guard let parsedVersion = PrivatePinyinVersion(version) else {
            throw PrivatePinyinUpdateManifestError.invalidVersion
        }
        guard build > 0 else {
            throw PrivatePinyinUpdateManifestError.invalidBuild
        }
        guard let parsedMinimumSystemVersion = PrivatePinyinVersion(minimumMacOSVersion) else {
            throw PrivatePinyinUpdateManifestError.invalidSystemVersion
        }
        guard ISO8601DateFormatter().date(from: publishedAt) != nil else {
            throw PrivatePinyinUpdateManifestError.invalidPublishedDate
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, trimmedTitle.utf8.count <= 160 else {
            throw PrivatePinyinUpdateManifestError.invalidTitle
        }
        guard (1 ... 12).contains(releaseNotes.count),
              releaseNotes.allSatisfy({ note in
                  let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                  return !trimmed.isEmpty && trimmed.utf8.count <= 500
              })
        else {
            throw PrivatePinyinUpdateManifestError.invalidReleaseNotes
        }

        let releasePage = try Self.validatedHTTPSURL(
            releasePageURL,
            allowedHost: allowedHost,
            error: .invalidReleasePageURL
        )
        let package = try Self.validatedHTTPSURL(
            packageURL,
            allowedHost: allowedHost,
            error: .invalidPackageURL
        )
        guard package.pathExtension.lowercased() == "pkg" else {
            throw PrivatePinyinUpdateManifestError.invalidPackageURL
        }
        guard packageSHA256.utf8.count == 64,
              packageSHA256.utf8.allSatisfy({ byte in
                  (48 ... 57).contains(byte) || (65 ... 70).contains(byte) || (97 ... 102).contains(byte)
              })
        else {
            throw PrivatePinyinUpdateManifestError.invalidPackageDigest
        }
        guard packageSizeBytes > 0, packageSizeBytes <= 2_147_483_648 else {
            throw PrivatePinyinUpdateManifestError.invalidPackageSize
        }

        return PrivatePinyinValidatedUpdate(
            manifest: self,
            parsedVersion: parsedVersion,
            parsedMinimumSystemVersion: parsedMinimumSystemVersion,
            releasePageURL: releasePage,
            packageURL: package
        )
    }

    private static func validatedHTTPSURL(
        _ value: String,
        allowedHost: String,
        error: PrivatePinyinUpdateManifestError
    ) throws -> URL {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == allowedHost.lowercased(),
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              url.port == nil || url.port == 443
        else {
            throw error
        }
        return url
    }
}

struct PrivatePinyinValidatedUpdate: Equatable {
    let manifest: PrivatePinyinUpdateManifest
    let parsedVersion: PrivatePinyinVersion
    let parsedMinimumSystemVersion: PrivatePinyinVersion
    let releasePageURL: URL
    let packageURL: URL

    func isNewer(than currentVersion: String, build currentBuild: Int) -> Bool {
        guard let parsedCurrentVersion = PrivatePinyinVersion(currentVersion) else {
            return false
        }
        if parsedVersion != parsedCurrentVersion {
            return parsedVersion > parsedCurrentVersion
        }
        return manifest.build > currentBuild
    }

    func supports(systemVersion: String) -> Bool {
        guard let parsedSystemVersion = PrivatePinyinVersion(systemVersion) else {
            return false
        }
        return parsedSystemVersion >= parsedMinimumSystemVersion
    }

    var formattedReleaseNotes: String {
        manifest.releaseNotes.map { "• \($0)" }.joined(separator: "\n")
    }
}
