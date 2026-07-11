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
        let prepared = try prepare(incoming)
        let startedAt = Date()
        let modelID = prepared.modelID
        do {
            let (data, response) = try await session.data(for: prepared.request)
            guard let http = response as? HTTPURLResponse else { throw ProviderConnectionError.malformedResponse }
            try? await record(statusCode: http.statusCode, body: data, modelID: modelID, startedAt: startedAt)
            return GatewayResponse(statusCode: http.statusCode, headers: responseHeaders(http), body: data)
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

    /// Streams bytes unchanged to the local client. Provider usage is parsed only after the stream ends.
    public func proxyStreaming(_ incoming: GatewayRequest, onResponse: @escaping @Sendable (GatewayResponseHead) -> Void, onChunk: @escaping @Sendable (Data) -> Void) async throws {
        let prepared = try prepare(incoming)
        let startedAt = Date()
        do {
            let (bytes, response) = try await session.bytes(for: prepared.request)
            guard let http = response as? HTTPURLResponse else { throw ProviderConnectionError.malformedResponse }
            onResponse(GatewayResponseHead(statusCode: http.statusCode, headers: responseHeaders(http)))
            var completeBody = Data()
            var chunk = Data()
            chunk.reserveCapacity(8_192)
            for try await byte in bytes {
                chunk.append(byte)
                completeBody.append(byte)
                if chunk.count >= 8_192 {
                    onChunk(chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty { onChunk(chunk) }
            try? await record(statusCode: http.statusCode, body: completeBody, modelID: prepared.modelID, startedAt: startedAt)
        } catch {
            try? await recordFailure(modelID: prepared.modelID, startedAt: startedAt)
            throw error
        }
    }

    private func prepare(_ incoming: GatewayRequest) throws -> (request: URLRequest, modelID: String?) {
        guard incoming.headers["authorization"] == "Bearer \(localToken)" else { throw GatewayAuthorizationError.missingOrInvalidToken }
        return (try makeUpstreamRequest(from: incoming), GatewayUsageExtractor.modelID(from: incoming.body))
    }

    private func record(statusCode: Int, body: Data, modelID: String?, startedAt: Date) async throws {
        let usage = GatewayUsageExtractor.usage(from: body, providerType: upstream.providerType)
        try await usageRecorder.record(GatewayUsageRecord(
            providerID: upstream.providerID,
            modelID: modelID,
            latencyMilliseconds: milliseconds(since: startedAt),
            statusCode: statusCode,
            inputTokens: usage?.input,
            outputTokens: usage?.output,
            totalTokens: usage?.total,
            source: usage == nil ? nil : .providerReported,
            errorCategory: (200..<300).contains(statusCode) ? nil : "http_\(statusCode)"
        ))
    }

    private func recordFailure(modelID: String?, startedAt: Date) async throws {
        try await usageRecorder.record(GatewayUsageRecord(providerID: upstream.providerID, modelID: modelID, latencyMilliseconds: milliseconds(since: startedAt), statusCode: nil, inputTokens: nil, outputTokens: nil, totalTokens: nil, source: nil, errorCategory: "network"))
    }

    private func responseHeaders(_ response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let key = item.key as? String, let value = item.value as? String, key.caseInsensitiveCompare("authorization") != .orderedSame {
                result[key] = value
            }
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
