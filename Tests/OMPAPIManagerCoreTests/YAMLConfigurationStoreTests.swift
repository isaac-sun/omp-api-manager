import Foundation
import XCTest
@testable import OMPAPIManagerCore

final class YAMLConfigurationStoreTests: XCTestCase {
    func testProviderUpdateKeepsUnknownFields() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let models = directory.appending(path: "models.yml")
        try """
        providers:
          existing:
            baseUrl: https://example.invalid/v1
            api: openai-completions
            customField: preserve-me
        futureTopLevel: true
        """.write(to: models, atomically: true, encoding: .utf8)
        let store = YAMLConfigurationStore()
        let current = try await store.readDocument(at: models)
        let provider = ProviderConfiguration(
            id: "managed",
            displayName: "Managed",
            type: .openAICompatible,
            ompAPIOverride: "openai-responses",
            baseURL: try XCTUnwrap(URL(string: "https://api.example.com/v1")),
            keychainAccount: "provider.managed",
            models: [ManagedModel(id: "test", displayName: "Test", contextWindow: 200_000, maxTokens: 32_000, inputPricePerMillion: 3, outputPricePerMillion: 15, cacheReadPricePerMillion: 0.3, cacheWritePricePerMillion: 3.75, inputModalities: ["text", "image"], supportsReasoning: true)]
        )
        let result = try await store.applyProvider(provider, at: models, expected: current.fingerprint)
        let text = try String(contentsOf: models, encoding: .utf8)
        XCTAssertTrue(text.contains("futureTopLevel"))
        XCTAssertTrue(text.contains("customField"))
        XCTAssertTrue(text.contains("managed"))
        XCTAssertTrue(text.contains("contextWindow"))
        XCTAssertTrue(text.contains("cacheRead"))
        XCTAssertTrue(text.contains("reasoning"))
        XCTAssertTrue(text.contains("openai-responses"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupURL.path))
    }

    func testFingerprintConflictPreventsOverwrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "models.yml")
        try "providers: {}\n".write(to: file, atomically: true, encoding: .utf8)
        let store = YAMLConfigurationStore()
        let snapshot = try await store.readDocument(at: file)
        try "providers: {}\nchanged: true\n".write(to: file, atomically: true, encoding: .utf8)
        do {
            _ = try await store.commit(document: snapshot.document, to: file, expected: snapshot.fingerprint)
            XCTFail("Expected a conflict")
        } catch let error as AppError {
            XCTAssertEqual(error, .configurationConflict(file))
        }
    }

    func testRestoreCreatesBackupOfCurrentFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "models.yml")
        try "providers:\n  original: {}\n".write(to: file, atomically: true, encoding: .utf8)
        let store = YAMLConfigurationStore()
        let original = try await store.readDocument(at: file)
        let updated = YAMLDocument(root: .object(["providers": .object(["updated": .object([:])])]))
        let firstChange = try await store.commit(document: updated, to: file, expected: original.fingerprint)
        let beforeRestore = try await store.readDocument(at: file)
        let restoreChange = try await store.restoreBackup(firstChange.backupURL, to: file, expected: beforeRestore.fingerprint)
        let restored = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(restored.contains("original"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoreChange.backupURL.path))
        let backups = try await store.listBackups(of: file)
        XCTAssertGreaterThanOrEqual(backups.count, 2)
    }
}
