import Foundation

public enum ProviderType: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case anthropicCompatible
    case customOpenAILike
    case customAnthropicLike

    public var ompAPI: String {
        switch self {
        case .openAICompatible, .customOpenAILike: "openai-completions"
        case .anthropicCompatible, .customAnthropicLike: "anthropic-messages"
        }
    }
}

public struct ModelIdentifier: Codable, Hashable, Sendable {
    public let providerID: String
    public let modelID: String

    public init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }

    public var rawValue: String { "\(providerID)/\(modelID)" }
}

public struct ProviderConfiguration: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var displayName: String
    public var type: ProviderType
    public var baseURL: URL
    public var keychainAccount: String
    public var models: [ManagedModel]
    public var defaultModelID: String?
    public var headers: [String: String]
    public var timeoutSeconds: Int
    public var isEnabled: Bool
    public var tags: [String]
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, displayName: String, type: ProviderType, baseURL: URL, keychainAccount: String, models: [ManagedModel] = [], defaultModelID: String? = nil, headers: [String: String] = [:], timeoutSeconds: Int = 60, isEnabled: Bool = true, tags: [String] = [], notes: String = "", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.baseURL = baseURL
        self.keychainAccount = keychainAccount
        self.models = models
        self.defaultModelID = defaultModelID
        self.headers = headers
        self.timeoutSeconds = timeoutSeconds
        self.isEnabled = isEnabled
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ManagedModel: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var displayName: String
    public var contextWindow: Int?
    public var maxTokens: Int?
    public var inputPricePerMillion: Decimal?
    public var outputPricePerMillion: Decimal?

    public init(id: String, displayName: String? = nil, contextWindow: Int? = nil, maxTokens: Int? = nil, inputPricePerMillion: Decimal? = nil, outputPricePerMillion: Decimal? = nil) {
        self.id = id
        self.displayName = displayName ?? id
        self.contextWindow = contextWindow
        self.maxTokens = maxTokens
        self.inputPricePerMillion = inputPricePerMillion
        self.outputPricePerMillion = outputPricePerMillion
    }
}

public struct ProviderCredentials: Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let headers: [String: String]

    public init(baseURL: URL, apiKey: String, headers: [String: String] = [:]) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
    }
}

public struct RemoteModel: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String?
    public init(id: String, displayName: String? = nil) { self.id = id; self.displayName = displayName }
}

public struct ConnectionTestResult: Sendable, Equatable {
    public let isSuccessful: Bool
    public let statusCode: Int?
    public let latency: Duration
    public let detail: String
}

public protocol ProviderAdapter: Sendable {
    var type: ProviderType { get }
    func validateEndpoint(_ endpoint: URL) throws
    func fetchModels(credentials: ProviderCredentials) async throws -> [RemoteModel]
    func testConnection(credentials: ProviderCredentials, model: String?) async throws -> ConnectionTestResult
}
