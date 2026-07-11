import Foundation
import XCTest
@testable import OMPAPIManagerCore

private actor InMemoryProviderRepository: ProviderRepository {
    private var providers: [ProviderConfiguration] = []
    func fetchAll() -> [ProviderConfiguration] { providers }
    func upsert(_ provider: ProviderConfiguration) { providers.removeAll { $0.id == provider.id }; providers.append(provider) }
    func delete(id: String) { providers.removeAll { $0.id == id } }
}

private final class KeychainSpy: SecretStoring, @unchecked Sendable {
    private(set) var saved: [String: String] = [:]
    func save(secret: String, account: String) throws { saved[account] = secret }
    func read(account: String) throws -> String { saved[account] ?? "" }
    func delete(account: String) throws { saved.removeValue(forKey: account) }
}

private struct FixedInstallationDetector: OMPInstallationDetecting {
    let installation: OMPInstallation
    func detectInstallation() async throws -> OMPInstallation { installation }
}

private struct ApplyingAdapterSpy: OMPConfigAdapter {
    let supportedVersionRange = "16.x"
    let result: ConfigChangeResult
    func readConfiguration(from installation: OMPInstallation) async throws -> OMPConfiguration { fatalError("Not used") }
    func applyProvider(_ provider: ProviderConfiguration, to installation: OMPInstallation) async throws -> ConfigChangeResult { result }
    func setDefaultModel(_ model: ModelIdentifier, in installation: OMPInstallation) async throws -> ConfigChangeResult { result }
    func validate(installation: OMPInstallation) async throws -> ValidationResult { ValidationResult(isValid: true) }
}

final class ProviderManagementServiceTests: XCTestCase {
    func testSaveDraftStoresOnlyMetadataInRepository() async throws {
        let repository = InMemoryProviderRepository()
        let keychain = KeychainSpy()
        let service = ProviderManagementService(repository: repository, keychain: keychain)
        let provider = ProviderConfiguration(
            id: "acme",
            displayName: "Acme",
            type: .openAICompatible,
            baseURL: try XCTUnwrap(URL(string: "https://api.acme.example/v1")),
            keychainAccount: "provider.acme"
        )
        try await service.saveDraft(provider, apiKey: "test-secret-not-a-real-key")
        XCTAssertEqual(keychain.saved["provider.acme"], "test-secret-not-a-real-key")
        let stored = try await service.listProviders()
        XCTAssertEqual(stored, [provider])
        XCTAssertFalse(String(describing: stored).contains("test-secret-not-a-real-key"))
    }

    func testRejectsInsecureRemoteHTTPProvider() async throws {
        let service = ProviderManagementService(repository: InMemoryProviderRepository(), keychain: KeychainSpy())
        let provider = ProviderConfiguration(
            id: "acme",
            displayName: "Acme",
            type: .openAICompatible,
            baseURL: try XCTUnwrap(URL(string: "http://api.acme.example/v1")),
            keychainAccount: "provider.acme"
        )
        do {
            try await service.saveDraft(provider, apiKey: "not-empty")
            XCTFail("Expected insecure endpoint rejection")
        } catch let error as AppError {
            guard case .invalidEndpoint = error else { return XCTFail("Unexpected error \(error)") }
        }
    }

    func testSaveAndApplyUsesVersionedAdapter() async throws {
        let repository = InMemoryProviderRepository()
        let keychain = KeychainSpy()
        let config = URL(fileURLWithPath: "/tmp/config.yml")
        let installation = OMPInstallation(executableURL: URL(fileURLWithPath: "/usr/bin/omp"), version: "16.4.2", configurationRoot: URL(fileURLWithPath: "/tmp"), agentDirectory: URL(fileURLWithPath: "/tmp"))
        let fingerprint = FileFingerprint(byteCount: 0, modifiedAt: .distantPast, digest: "test")
        let expected = ConfigChangeResult(changedURL: config, backupURL: config.appendingPathExtension("backup"), fingerprint: fingerprint)
        let service = ProviderManagementService(
            repository: repository,
            keychain: keychain,
            installationDetector: FixedInstallationDetector(installation: installation),
            configAdapter: ApplyingAdapterSpy(result: expected)
        )
        let provider = ProviderConfiguration(id: "acme", displayName: "Acme", type: .openAICompatible, baseURL: try XCTUnwrap(URL(string: "https://api.acme.example/v1")), keychainAccount: "provider.acme")
        let result = try await service.saveAndApply(provider, apiKey: "test-secret-not-a-real-key")
        XCTAssertEqual(result, expected)
        let drafts = try await service.listProviders()
        XCTAssertEqual(drafts, [provider])
    }

    func testImportNewAPIConnectionStoresOnlyKeychainSecretAndNormalizesV1URL() async throws {
        let repository = InMemoryProviderRepository()
        let keychain = KeychainSpy()
        let service = ProviderManagementService(repository: repository, keychain: keychain)
        let source = #"{"_type":"newapi_channel_conn","key":"test-newapi-key","url":"https://api.example.test"}"#

        let provider = try await service.importNewAPIChannelConnection(source, apply: false)

        XCTAssertEqual(provider.id, "newapi-api-example-test")
        XCTAssertEqual(provider.type, .customOpenAILike)
        XCTAssertEqual(provider.baseURL, try XCTUnwrap(URL(string: "https://api.example.test/v1")))
        XCTAssertEqual(keychain.saved[provider.keychainAccount], "test-newapi-key")
        let stored = try await service.listProviders()
        XCTAssertEqual(stored, [provider])
        XCTAssertFalse(String(describing: stored).contains("test-newapi-key"))
    }

    func testImportNewAPIConnectionRejectsUnexpectedConnectionType() async throws {
        let service = ProviderManagementService(repository: InMemoryProviderRepository(), keychain: KeychainSpy())
        let source = #"{"_type":"other_connection","key":"test-key","url":"https://api.example.test/v1"}"#

        do {
            _ = try await service.importNewAPIChannelConnection(source, apply: false)
            XCTFail("Expected unsupported connection type rejection")
        } catch let error as AppError {
            XCTAssertEqual(error, .invalidProvider("Unsupported connection type. Expected newapi_channel_conn."))
        }
    }
}
