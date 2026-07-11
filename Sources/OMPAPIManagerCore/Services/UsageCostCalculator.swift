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

public struct UsageSummary: Sendable, Equatable {
    public let requestCount: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let errorCount: Int
    public let averageLatencyMilliseconds: Int

    public init(requestCount: Int, inputTokens: Int, outputTokens: Int, totalTokens: Int, errorCount: Int, averageLatencyMilliseconds: Int) {
        self.requestCount = requestCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.errorCount = errorCount
        self.averageLatencyMilliseconds = averageLatencyMilliseconds
    }
}

public enum UsageExportFormat: String, CaseIterable, Sendable {
    case csv
    case json
}

public struct UsageExporter: Sendable {
    public init() {}

    public func data(records: [GatewayUsageRecord], format: UsageExportFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(records)
        case .csv:
            let header = "id,provider_id,model_id,occurred_at,latency_ms,status_code,input_tokens,output_tokens,total_tokens,source,error_category"
            let rows = records.map(csvRow)
            return Data(([header] + rows).joined(separator: "\n").utf8)
        }
    }

    private func csvRow(_ record: GatewayUsageRecord) -> String {
        let values: [String] = [
            record.id.uuidString,
            record.providerID,
            record.modelID ?? "",
            ISO8601DateFormatter().string(from: record.occurredAt),
            String(record.latencyMilliseconds),
            record.statusCode.map { String($0) } ?? "",
            record.inputTokens.map { String($0) } ?? "",
            record.outputTokens.map { String($0) } ?? "",
            record.totalTokens.map { String($0) } ?? "",
            record.source?.rawValue ?? "",
            record.errorCategory ?? ""
        ]
        return values.map(csvEscape).joined(separator: ",")
    }

    private func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
