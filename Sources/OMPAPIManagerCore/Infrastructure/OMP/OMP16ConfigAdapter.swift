import Foundation

/// Write adapter for OMP 16.x. It operates only on the documented `models.yml` schema.
public struct OMP16ConfigAdapter: OMPConfigAdapter {
    public let supportedVersionRange = "16.x"
    private let store: YAMLConfigurationStore

    public init(store: YAMLConfigurationStore = YAMLConfigurationStore()) { self.store = store }

    public func readConfiguration(from installation: OMPInstallation) async throws -> OMPConfiguration {
        let config = try await store.readDocument(at: installation.configURL)
        let models = try await store.readDocument(at: installation.modelsURL)
        return OMPConfiguration(config: config.document, models: models.document, configFingerprint: config.fingerprint, modelsFingerprint: models.fingerprint)
    }

    public func applyProvider(_ provider: ProviderConfiguration, to installation: OMPInstallation) async throws -> ConfigChangeResult {
        let models = try await store.readDocument(at: installation.modelsURL)
        return try await store.applyProvider(provider, at: installation.modelsURL, expected: models.fingerprint)
    }

    public func setDefaultModel(_ model: ModelIdentifier, in installation: OMPInstallation) async throws -> ConfigChangeResult {
        let config = try await store.readDocument(at: installation.configURL)
        guard case .object(var root) = config.document.root else { throw AppError.configurationParseFailed("config.yml root must be a mapping") }
        var roles: [String: YAMLValue]
        if case .object(let existing) = root["modelRoles"] { roles = existing } else { roles = [:] }
        roles["default"] = .string(model.rawValue)
        root["modelRoles"] = .object(roles)
        return try await store.commit(document: YAMLDocument(root: .object(root)), to: installation.configURL, expected: config.fingerprint)
    }

    public func validate(installation: OMPInstallation) async throws -> ValidationResult {
        _ = try await store.readDocument(at: installation.configURL)
        _ = try await store.readDocument(at: installation.modelsURL)
        return ValidationResult(isValid: true, messages: ["YAML parsed. OMP exposes no documented standalone validation or reload command in 16.4.2."])
    }
}
