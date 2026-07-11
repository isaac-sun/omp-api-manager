import Foundation
import XCTest
@testable import OMPAPIManagerCore

private struct StubInstallationDetector: OMPInstallationDetecting {
    let installation: OMPInstallation
    func detectInstallation() async throws -> OMPInstallation { installation }
}

final class OMPConfigurationInspectionServiceTests: XCTestCase {
    func testReadsProviderIDsAndDefaultModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let agent = directory.appending(path: "agent")
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "modelRoles:\n  default: acme/test\n".write(to: agent.appending(path: "config.yml"), atomically: true, encoding: .utf8)
        try "providers:\n  acme: {}\n  beta: {}\n".write(to: agent.appending(path: "models.yml"), atomically: true, encoding: .utf8)
        let installation = OMPInstallation(executableURL: URL(fileURLWithPath: "/usr/bin/omp"), version: "16.4.2", configurationRoot: directory, agentDirectory: agent)
        let service = OMPConfigurationInspectionService(detector: StubInstallationDetector(installation: installation))
        let snapshot = try await service.inspectCurrentInstallation()
        XCTAssertEqual(snapshot.providerIDs, ["acme", "beta"])
        XCTAssertEqual(snapshot.defaultModel, "acme/test")
        XCTAssertTrue(snapshot.isWriteSupported)
        if case .valid = snapshot.configStatus {} else { XCTFail("config.yml should be valid") }
    }

    func testUnknownVersionIsReadOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let agent = directory.appending(path: "agent")
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let installation = OMPInstallation(executableURL: URL(fileURLWithPath: "/usr/bin/omp"), version: "17.0.0", configurationRoot: directory, agentDirectory: agent)
        let service = OMPConfigurationInspectionService(detector: StubInstallationDetector(installation: installation))
        let snapshot = try await service.inspectCurrentInstallation()
        XCTAssertFalse(snapshot.isWriteSupported)
        XCTAssertTrue(snapshot.diagnostics.contains { $0.contains("read-only") })
    }
}
