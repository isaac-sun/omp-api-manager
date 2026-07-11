import Foundation

public struct AnthropicCompatibleAdapter: ProviderAdapter {
    public let type: ProviderType = .anthropicCompatible
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func validateEndpoint(_ endpoint: URL) throws {
        guard let scheme = endpoint.scheme?.lowercased(), ["https", "http"].contains(scheme), endpoint.host != nil else {
            throw AppError.invalidEndpoint(endpoint.absoluteString)
        }
        if scheme == "http", endpoint.host != "localhost", endpoint.host != "127.0.0.1" {
            throw AppError.invalidEndpoint("HTTP is limited to localhost endpoints")
        }
    }

    public func fetchModels(credentials: ProviderCredentials) async throws -> [RemoteModel] {
        try validateEndpoint(credentials.baseURL)
        var request = baseRequest(url: credentials.baseURL.appending(path: "models"), credentials: credentials)
        request.httpMethod = "GET"
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw ProviderHTTPErrorMapper.map(error) }
        _ = try ProviderHTTPErrorMapper.validate(response, data: data)
        struct Response: Decodable {
            let data: [Item]
            struct Item: Decodable { let id: String; let display_name: String? }
        }
        do { return try JSONDecoder().decode(Response.self, from: data).data.map { RemoteModel(id: $0.id, displayName: $0.display_name) } }
        catch { throw ProviderConnectionError.malformedResponse }
    }

    public func testConnection(credentials: ProviderCredentials, model: String?) async throws -> ConnectionTestResult {
        guard let model else {
            let started = ContinuousClock.now
            _ = try await fetchModels(credentials: credentials)
            return ConnectionTestResult(isSuccessful: true, statusCode: 200, latency: started.duration(to: .now), detail: "Authentication accepted; no model was selected for a Messages API test.")
        }
        let started = ContinuousClock.now
        var request = baseRequest(url: credentials.baseURL.appending(path: "messages"), credentials: credentials)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "max_tokens": 1, "messages": [["role": "user", "content": "Reply with OK."]]])
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw ProviderHTTPErrorMapper.map(error) }
        let http = try ProviderHTTPErrorMapper.validate(response, data: data)
        return ConnectionTestResult(isSuccessful: true, statusCode: http.statusCode, latency: started.duration(to: .now), detail: "Authentication and selected model were accepted.")
    }

    private func baseRequest(url: URL, credentials: ProviderCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        credentials.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }
}
