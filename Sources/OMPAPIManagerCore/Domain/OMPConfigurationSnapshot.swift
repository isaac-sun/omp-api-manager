import Foundation

public enum ConfigurationFileStatus: Sendable, Equatable {
    case valid(FileFingerprint)
    case missing
    case invalid(String)
}

public struct OMPConfigurationSnapshot: Sendable, Equatable {
    public let installation: OMPInstallation
    public let isWriteSupported: Bool
    public let configStatus: ConfigurationFileStatus
    public let modelsStatus: ConfigurationFileStatus
    public let providerIDs: [String]
    public let defaultModel: String?
    public let diagnostics: [String]

    public init(installation: OMPInstallation, isWriteSupported: Bool, configStatus: ConfigurationFileStatus, modelsStatus: ConfigurationFileStatus, providerIDs: [String], defaultModel: String?, diagnostics: [String]) {
        self.installation = installation
        self.isWriteSupported = isWriteSupported
        self.configStatus = configStatus
        self.modelsStatus = modelsStatus
        self.providerIDs = providerIDs
        self.defaultModel = defaultModel
        self.diagnostics = diagnostics
    }
}

public protocol OMPConfigurationInspecting: Sendable {
    func inspectCurrentInstallation() async throws -> OMPConfigurationSnapshot
}
