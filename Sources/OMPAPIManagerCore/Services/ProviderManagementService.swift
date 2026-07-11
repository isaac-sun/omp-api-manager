import Foundation

public struct ProviderManagementService: Sendable {
    private let repository: any ProviderRepository
    private let keychain: any SecretStoring
    private let installationDetector: any OMPInstallationDetecting
    private let configAdapter: any OMPConfigAdapter

    public init(repository: any ProviderRepository, keychain: any SecretStoring = KeychainService(), installationDetector: any OMPInstallationDetecting = OMPInstallationDetector(), configAdapter: any OMPConfigAdapter = OMP16ConfigAdapter()) {
        self.repository = repository
        self.keychain = keychain
        self.installationDetector = installationDetector
        self.configAdapter = configAdapter
    }

    public func listProviders() async throws -> [ProviderConfiguration] {
        try await repository.fetchAll()
    }

    /// Persists only non-secret provider metadata; the API key is stored in macOS Keychain.
    public func saveDraft(_ provider: ProviderConfiguration, apiKey: String) async throws {
        try validate(provider)
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidProvider("An API key is required.")
        }
        try keychain.save(secret: apiKey, account: provider.keychainAccount)
        try await repository.upsert(provider)
    }

    public func deleteDraft(_ provider: ProviderConfiguration) async throws {
        try await repository.delete(id: provider.id)
        try keychain.delete(account: provider.keychainAccount)
    }

    /// A failed apply leaves the validated provider as a local draft and never modifies an unsupported OMP version.
    public func saveAndApply(_ provider: ProviderConfiguration, apiKey: String) async throws -> ConfigChangeResult {
        try await saveDraft(provider, apiKey: apiKey)
        let installation = try await installationDetector.detectInstallation()
        guard installation.version.split(separator: ".").first == "16" else {
            throw AppError.unsupportedOMPVersion(installation.version)
        }
        return try await configAdapter.applyProvider(provider, to: installation)
    }

    private func validate(_ provider: ProviderConfiguration) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        guard !provider.id.isEmpty,
              provider.id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AppError.invalidProvider("ID can contain only lowercase letters, numbers, hyphens, and underscores.")
        }
        guard !provider.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidProvider("A display name is required.")
        }
        guard provider.timeoutSeconds >= 1, provider.timeoutSeconds <= 600 else {
            throw AppError.invalidProvider("Timeout must be between 1 and 600 seconds.")
        }
        try validateEndpoint(provider.baseURL)
    }

    private func validateEndpoint(_ endpoint: URL) throws {
        guard let scheme = endpoint.scheme?.lowercased(), ["https", "http"].contains(scheme), endpoint.host != nil else {
            throw AppError.invalidEndpoint(endpoint.absoluteString)
        }
        if scheme == "http", endpoint.host != "localhost", endpoint.host != "127.0.0.1" {
            throw AppError.invalidEndpoint("HTTP is limited to localhost endpoints")
        }
    }
}
