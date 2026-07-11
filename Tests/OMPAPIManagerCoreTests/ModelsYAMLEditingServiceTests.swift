import Foundation
import XCTest
@testable import OMPAPIManagerCore

final class ModelsYAMLEditingServiceTests: XCTestCase {
    func testLoadRedactsSecretAndSavePreservesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "models.yml")
        try """
        providers:
          acme:
            baseUrl: https://old.example/v1
            apiKey: "!security find-generic-password -s com.omp-api-manager -a provider.acme -w"
            api: openai-completions
        """.write(to: file, atomically: true, encoding: .utf8)
        let service = ModelsYAMLEditingService()
        let loaded = try await service.load(at: file)
        XCTAssertFalse(loaded.text.contains("find-generic-password"))
        XCTAssertTrue(loaded.text.contains(ModelsYAMLEditingService.redactedSecretMarker))
        let edited = loaded.text.replacingOccurrences(of: "https://old.example/v1", with: "https://new.example/v1")
        _ = try await service.save(editedYAML: edited, to: file, expected: loaded.fingerprint)
        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(saved.contains("https://new.example/v1"))
        XCTAssertTrue(saved.contains("find-generic-password"))
    }

    func testRejectsPlaintextSecretEnteredInEditor() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "models.yml")
        try "providers: {}\n".write(to: file, atomically: true, encoding: .utf8)
        let service = ModelsYAMLEditingService()
        let loaded = try await service.load(at: file)
        let edited = """
        providers:
          acme:
            apiKey: not-allowed
        """
        do {
            _ = try await service.save(editedYAML: edited, to: file, expected: loaded.fingerprint)
            XCTFail("Expected plaintext secret rejection")
        } catch let error as AppError {
            guard case .invalidProvider = error else { return XCTFail("Unexpected error \(error)") }
        }
    }

    func testPreservesLegacySecretWithoutDisplayingIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "models.yml")
        try """
        providers:
          legacy:
            apiKey: legacy-value-never-shown-to-ui
            baseUrl: https://old.example/v1
        """.write(to: file, atomically: true, encoding: .utf8)
        let service = ModelsYAMLEditingService()
        let loaded = try await service.load(at: file)
        XCTAssertFalse(loaded.text.contains("legacy-value-never-shown-to-ui"))
        let edited = loaded.text.replacingOccurrences(of: "https://old.example/v1", with: "https://new.example/v1")
        _ = try await service.save(editedYAML: edited, to: file, expected: loaded.fingerprint)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("legacy-value-never-shown-to-ui"))
    }
}
