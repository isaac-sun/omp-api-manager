import Foundation

public struct UsageRecord: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable { case providerReported, locallyEstimated }
    public let inputTokens: Int
    public let outputTokens: Int
    public let source: Source
    public init(inputTokens: Int, outputTokens: Int, source: Source) { self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.source = source }
}

public struct UsageCostCalculator: Sendable {
    public init() {}
    public func estimatedCost(for usage: UsageRecord, model: ManagedModel) -> Decimal? {
        guard let inputPrice = model.inputPricePerMillion, let outputPrice = model.outputPricePerMillion else { return nil }
        return (Decimal(usage.inputTokens) / 1_000_000 * inputPrice) + (Decimal(usage.outputTokens) / 1_000_000 * outputPrice)
    }
}

public struct GatewayUsageRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let providerID: String
    public let modelID: String?
    public let occurredAt: Date
    public let latencyMilliseconds: Int
    public let statusCode: Int?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let source: UsageRecord.Source?
    public let errorCategory: String?

    public init(id: UUID = UUID(), providerID: String, modelID: String?, occurredAt: Date = .now, latencyMilliseconds: Int, statusCode: Int?, inputTokens: Int?, outputTokens: Int?, totalTokens: Int?, source: UsageRecord.Source?, errorCategory: String?) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.occurredAt = occurredAt
        self.latencyMilliseconds = latencyMilliseconds
        self.statusCode = statusCode
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.source = source
        self.errorCategory = errorCategory
    }
}

public protocol UsageRecording: Sendable {
    func record(_ usage: GatewayUsageRecord) async throws
    func recentUsage(limit: Int) async throws -> [GatewayUsageRecord]
}
