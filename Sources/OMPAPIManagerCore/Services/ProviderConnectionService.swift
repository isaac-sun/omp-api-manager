import Foundation

public protocol ProviderAdapterResolving: Sendable {
    func adapter(for type: ProviderType) -> any ProviderAdapter
}

public struct DefaultProviderAdapterResolver: ProviderAdapterResolving {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func adapter(for type: ProviderType) -> any ProviderAdapter {
        switch type {
        case .openAICompatible, .customOpenAILike: OpenAICompatibleAdapter(session: session)
        case .anthropicCompatible, .customAnthropicLike: AnthropicCompatibleAdapter(session: session)
        }
    }
}

public struct ProviderConnectionService: Sendable {
    private let resolver: any ProviderAdapterResolving
    public init(resolver: any ProviderAdapterResolving = DefaultProviderAdapterResolver()) { self.resolver = resolver }

    public func fetchModels(type: ProviderType, baseURL: URL, apiKey: String, headers: [String: String] = [:]) async throws -> [RemoteModel] {
        try await resolver.adapter(for: type).fetchModels(credentials: ProviderCredentials(baseURL: baseURL, apiKey: apiKey, headers: headers))
    }

    public func testConnection(type: ProviderType, baseURL: URL, apiKey: String, model: String?) async throws -> ConnectionTestResult {
        try await resolver.adapter(for: type).testConnection(credentials: ProviderCredentials(baseURL: baseURL, apiKey: apiKey), model: model)
    }
}
