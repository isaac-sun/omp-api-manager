import Foundation

public struct GatewayProxyProcessor: Sendable {
    private let upstream: GatewayUpstream
    private let localToken: String
    private let keychain: any SecretStoring
    private let usageRecorder: any UsageRecording
    private let session: URLSession

    public init(upstream: GatewayUpstream, localToken: String, keychain: any SecretStoring = KeychainService(), usageRecorder: any UsageRecording, session: URLSession = .shared) {
        self.upstream = upstream
        self.localToken = localToken
        self.keychain = keychain
        self.usageRecorder = usageRecorder
        self.session = session
    }

    public func proxy(_ incoming: GatewayRequest) async throws -> GatewayResponse {
        guard incoming.headers["authorization"] == "Bearer \(localToken)" else { throw GatewayAuthorizationError.missingOrInvalidToken }
        let startedAt = Date()
        let modelID = GatewayUsageExtractor.modelID(from: incoming.body)
        do {
            let request = try makeUpstreamRequest(from: incoming)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderConnectionError.malformedResponse }
            let usage = GatewayUsageExtractor.usage(from: data, providerType: upstream.providerType)
            try? await usageRecorder.record(GatewayUsageRecord(
                providerID: upstream.providerID,
                modelID: modelID,
                latencyMilliseconds: milliseconds(since: startedAt),
                statusCode: http.statusCode,
                inputTokens: usage?.input,
                outputTokens: usage?.output,
                totalTokens: usage?.total,
                source: usage == nil ? nil : .providerReported,
                errorCategory: (200..<300).contains(http.statusCode) ? nil : "http_\(http.statusCode)"
            ))
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                if let key = item.key as? String, let value = item.value as? String, key.caseInsensitiveCompare("authorization") != .orderedSame {
                    result[key] = value
                }
            }
            return GatewayResponse(statusCode: http.statusCode, headers: headers, body: data)
        } catch {
            try? await usageRecorder.record(GatewayUsageRecord(
                providerID: upstream.providerID,
                modelID: modelID,
                latencyMilliseconds: milliseconds(since: startedAt),
                statusCode: nil,
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: nil,
                source: nil,
                errorCategory: "network"
            ))
            throw error
        }
    }

    private func makeUpstreamRequest(from incoming: GatewayRequest) throws -> URLRequest {
        guard let target = URLComponents(string: incoming.target), var components = URLComponents(url: upstream.baseURL, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidEndpoint(incoming.target)
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetPath = target.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, targetPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.query = target.query
        guard let url = components.url else { throw AppError.invalidEndpoint(incoming.target) }
        var request = URLRequest(url: url)
        request.httpMethod = incoming.method
        request.httpBody = incoming.body
        for (name, value) in incoming.headers where !isHopByHopOrCredentialHeader(name) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let apiKey = try keychain.read(account: upstream.keychainAccount)
        switch upstream.providerType {
        case .openAICompatible, .customOpenAILike:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropicCompatible, .customAnthropicLike:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            if request.value(forHTTPHeaderField: "anthropic-version") == nil {
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
        }
        return request
    }

    private func isHopByHopOrCredentialHeader(_ name: String) -> Bool {
        ["authorization", "host", "connection", "transfer-encoding", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "upgrade"].contains(name.lowercased())
    }

    private func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1_000)
    }
}
