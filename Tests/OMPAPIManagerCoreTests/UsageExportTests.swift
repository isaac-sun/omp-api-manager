import Foundation
import XCTest
@testable import OMPAPIManagerCore

final class UsageExportTests: XCTestCase {
    func testExportsCSVAndJSONWithoutRequestContents() throws {
        let record = GatewayUsageRecord(providerID: "acme", modelID: "gpt-test", latencyMilliseconds: 8, statusCode: 200, inputTokens: 2, outputTokens: 1, totalTokens: 3, source: .providerReported, errorCategory: nil)
        let exporter = UsageExporter()
        let csv = try String(decoding: exporter.data(records: [record], format: .csv), as: UTF8.self)
        let json = try String(decoding: exporter.data(records: [record], format: .json), as: UTF8.self)
        XCTAssertTrue(csv.contains("provider_id"))
        XCTAssertTrue(csv.contains("acme"))
        XCTAssertTrue(json.contains("gpt-test"))
        XCTAssertFalse(csv.contains("prompt"))
    }
}
