import XCTest
@testable import OMPAPIManagerCore

final class UsageCostCalculatorTests: XCTestCase {
    func testCalculatesCostAndRetainsSource() {
        let model = ManagedModel(id: "example", inputPricePerMillion: 2, outputPricePerMillion: 6)
        let usage = UsageRecord(inputTokens: 500_000, outputTokens: 250_000, source: .providerReported)
        XCTAssertEqual(UsageCostCalculator().estimatedCost(for: usage, model: model), 2.5)
        XCTAssertEqual(usage.source, .providerReported)
    }
}
