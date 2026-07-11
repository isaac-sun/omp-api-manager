import Foundation

public struct SoftwareVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    private let prereleaseIdentifiers: [PrereleaseIdentifier]

    public init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 64 else { return nil }

        let versionText: Substring
        if trimmed.first == "v" || trimmed.first == "V" {
            versionText = trimmed.dropFirst()
        } else {
            versionText = Substring(trimmed)
        }

        let buildParts = versionText.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard buildParts.count <= 2, !buildParts[0].isEmpty else { return nil }
        if buildParts.count == 2 {
            guard Self.validIdentifiers(buildParts[1], allowLeadingZeroes: true) else { return nil }
        }

        let prereleaseParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard !prereleaseParts[0].isEmpty else { return nil }

        let numberParts = prereleaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numberParts.count == 3,
              let major = Self.parseCoreNumber(numberParts[0]),
              let minor = Self.parseCoreNumber(numberParts[1]),
              let patch = Self.parseCoreNumber(numberParts[2]) else { return nil }

        let prereleaseIdentifiers: [PrereleaseIdentifier]
        if prereleaseParts.count == 2 {
            guard Self.validIdentifiers(prereleaseParts[1], allowLeadingZeroes: false) else { return nil }
            prereleaseIdentifiers = prereleaseParts[1].split(separator: ".").map { identifier in
                if let number = Int(identifier), identifier == "0" || !identifier.hasPrefix("0") {
                    return .numeric(number)
                }
                return .text(String(identifier))
            }
        } else {
            prereleaseIdentifiers = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
    }

    public var isStable: Bool { prereleaseIdentifiers.isEmpty }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prereleaseIdentifiers.isEmpty else { return core }
        return core + "-" + prereleaseIdentifiers.map(\.description).joined(separator: ".")
    }

    public static func < (lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore { return lhsCore.lexicographicallyPrecedes(rhsCore) }

        if lhs.prereleaseIdentifiers.isEmpty { return false }
        if rhs.prereleaseIdentifiers.isEmpty { return true }

        for (left, right) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if left == right { continue }
            return left < right
        }
        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }

    private static func parseCoreNumber(_ value: Substring) -> Int? {
        guard !value.isEmpty,
              value == "0" || !value.hasPrefix("0"),
              value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(value), number <= 999_999 else { return nil }
        return number
    }

    private static func validIdentifiers(_ value: Substring, allowLeadingZeroes: Bool) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.utf8.allSatisfy({ byte in
                      (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
                  }) else { return false }
            if !allowLeadingZeroes,
               identifier.utf8.allSatisfy({ (48...57).contains($0) }),
               identifier.count > 1,
               identifier.hasPrefix("0") { return false }
            return true
        }
    }
}

private enum PrereleaseIdentifier: Sendable, Hashable, Comparable, CustomStringConvertible {
    case numeric(Int)
    case text(String)

    var description: String {
        switch self {
        case .numeric(let value): String(value)
        case .text(let value): value
        }
    }

    static func < (lhs: PrereleaseIdentifier, rhs: PrereleaseIdentifier) -> Bool {
        switch (lhs, rhs) {
        case (.numeric(let left), .numeric(let right)): left < right
        case (.numeric, .text): true
        case (.text, .numeric): false
        case (.text(let left), .text(let right)): left < right
        }
    }
}

public struct SoftwareRelease: Sendable, Equatable {
    public let version: SoftwareVersion
    public let tagName: String
    public let title: String
    public let notes: String
    public let publishedAt: Date?
    public let officialReleaseURL: URL

    public init(version: SoftwareVersion, tagName: String, title: String, notes: String, publishedAt: Date?, officialReleaseURL: URL) {
        self.version = version
        self.tagName = tagName
        self.title = title
        self.notes = notes
        self.publishedAt = publishedAt
        self.officialReleaseURL = officialReleaseURL
    }
}

public struct SoftwareUpdateCheck: Sendable, Equatable {
    public let currentVersion: SoftwareVersion
    public let latestRelease: SoftwareRelease

    public init(currentVersion: SoftwareVersion, latestRelease: SoftwareRelease) {
        self.currentVersion = currentVersion
        self.latestRelease = latestRelease
    }

    public var isUpdateAvailable: Bool { currentVersion < latestRelease.version }
}

public enum SoftwareUpdateError: Error, LocalizedError, Sendable, Equatable {
    case invalidCurrentVersion
    case noPublishedRelease
    case rateLimited(retryAfter: Date?)
    case unexpectedHTTPStatus(Int)
    case invalidResponse
    case untrustedResponse
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            "The installed app version could not be determined."
        case .noPublishedRelease:
            "No published release is available on GitHub."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "GitHub temporarily limited update checks. Try again after \(retryAfter.formatted(date: .abbreviated, time: .shortened))."
            } else {
                "GitHub temporarily limited update checks. Try again later."
            }
        case .unexpectedHTTPStatus(let status):
            "GitHub returned HTTP \(status) while checking for updates."
        case .invalidResponse:
            "GitHub returned an invalid update response."
        case .untrustedResponse:
            "The update response did not come from the expected GitHub endpoint."
        case .responseTooLarge:
            "The update response was unexpectedly large."
        }
    }
}
