import Foundation
import XCTest
@testable import OMPAPIManagerCore

private struct StubExecutor: ProcessExecuting {
    let output: String
    func run(executable: URL, arguments: [String]) async throws -> String { output }
}

final class OMPInstallationDetectorTests: XCTestCase {
    func testResolvesAgentDirectoryOverride() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/omp") else { throw XCTSkip("Homebrew OMP is unavailable on this host") }
        let detector = OMPInstallationDetector(
            environment: ["PI_CODING_AGENT_DIR": "/tmp/omp-test/agent", "PI_CONFIG_DIR": "/tmp/ignored"],
            executor: StubExecutor(output: "omp/16.4.2\n")
        )
        let installation = try await detector.detectInstallation()
        XCTAssertEqual(installation.agentDirectory.path, "/tmp/omp-test/agent")
        XCTAssertEqual(installation.configurationRoot.path, "/tmp/omp-test")
    }

    func testDetectsUnrecognizedMajorVersionForReadOnlyInspection() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/omp") else { throw XCTSkip("Homebrew OMP is unavailable on this host") }
        let detector = OMPInstallationDetector(executor: StubExecutor(output: "omp/17.0.0\n"))
        let installation = try await detector.detectInstallation()
        XCTAssertEqual(installation.version, "17.0.0")
    }
}
