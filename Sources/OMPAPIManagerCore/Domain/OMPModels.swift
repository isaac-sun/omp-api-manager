import Foundation

public struct OMPInstallation: Sendable, Equatable {
    public let executableURL: URL
    public let version: String
    public let configurationRoot: URL
    public let agentDirectory: URL
    public let configURL: URL
    public let modelsURL: URL

    public init(executableURL: URL, version: String, configurationRoot: URL, agentDirectory: URL) {
        self.executableURL = executableURL
        self.version = version
        self.configurationRoot = configurationRoot
        self.agentDirectory = agentDirectory
        self.configURL = agentDirectory.appending(path: "config.yml")
        self.modelsURL = agentDirectory.appending(path: "models.yml")
    }
}

public protocol OMPInstallationDetecting: Sendable {
    func detectInstallation() async throws -> OMPInstallation
}

public struct FileFingerprint: Sendable, Equatable, Codable {
    public let byteCount: Int
    public let modifiedAt: Date
    public let digest: String

    public init(byteCount: Int, modifiedAt: Date, digest: String) {
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
        self.digest = digest
    }
}

public struct OMPConfiguration: Sendable, Equatable {
    public let config: YAMLDocument
    public let models: YAMLDocument
    public let configFingerprint: FileFingerprint
    public let modelsFingerprint: FileFingerprint
}

public struct ConfigChangeResult: Sendable, Equatable {
    public let changedURL: URL
    public let backupURL: URL
    public let fingerprint: FileFingerprint
}

public struct ConfigurationBackup: Sendable, Equatable, Identifiable {
    public let url: URL
    public let createdAt: Date

    public var id: URL { url }

    public init(url: URL, createdAt: Date) {
        self.url = url
        self.createdAt = createdAt
    }
}

public struct ValidationResult: Sendable, Equatable {
    public let isValid: Bool
    public let messages: [String]

    public init(isValid: Bool, messages: [String] = []) {
        self.isValid = isValid
        self.messages = messages
    }
}

public protocol OMPConfigAdapter: Sendable {
    var supportedVersionRange: String { get }
    func readConfiguration(from installation: OMPInstallation) async throws -> OMPConfiguration
    func applyProvider(_ provider: ProviderConfiguration, to installation: OMPInstallation) async throws -> ConfigChangeResult
    func setDefaultModel(_ model: ModelIdentifier, in installation: OMPInstallation) async throws -> ConfigChangeResult
    func validate(installation: OMPInstallation) async throws -> ValidationResult
}
