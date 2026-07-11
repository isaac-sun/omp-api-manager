import Foundation
import XCTest
@testable import OMPAPIManagerCore

private final class GatewayMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    private static let lock = NSLock()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.lastRequest = request
        let handler = Self.handler
        Self.lock.unlock()
        let result = handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func configure(handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        lock.lock()
        self.handler = handler
        lastRequest = nil
        lock.unlock()
    }
}

private final class GatewayKeychainDouble: SecretStoring, @unchecked Sendable {
    let values: [String: String]
    init(values: [String: String]) { self.values = values }
    func save(secret: String, account: String) throws {}
    func read(account: String) throws -> String { values[account] ?? "" }
    func delete(account: String) throws {}
}

private actor InMemoryUsageRecorder: UsageRecording {
    private var records: [GatewayUsageRecord] = []
    func record(_ usage: GatewayUsageRecord) { records.append(usage) }
    func recentUsage(limit: Int) -> [GatewayUsageRecord] { Array(records.suffix(limit)) }
}

final class GatewayTests: XCTestCase {
    func testProxyReplacesLocalTokenAndRecordsProviderUsage() async throws {
        GatewayMockURLProtocol.configure { request in
            XCTAssertEqual(request.url?.absoluteString, "https://upstream.example/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer upstream-secret")
            return (200, Data(#"{"usage":{"prompt_tokens":12,"completion_tokens":3,"total_tokens":15}}"#.utf8))
        }
        let usage = InMemoryUsageRecorder()
        let processor = GatewayProxyProcessor(
            upstream: GatewayUpstream(providerID: "acme", providerType: .openAICompatible, baseURL: try XCTUnwrap(URL(string: "https://upstream.example/v1")), keychainAccount: "provider.acme"),
            localToken: "local-token",
            keychain: GatewayKeychainDouble(values: ["provider.acme": "upstream-secret"]),
            usageRecorder: usage,
            session: mockSession()
        )
        let request = GatewayRequest(method: "POST", target: "/chat/completions", headers: ["authorization": "Bearer local-token", "content-type": "application/json"], body: Data(#"{"model":"gpt-test"}"#.utf8))
        let response = try await processor.proxy(request)
        XCTAssertEqual(response.statusCode, 200)
        let records = await usage.recentUsage(limit: 10)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].providerID, "acme")
        XCTAssertEqual(records[0].modelID, "gpt-test")
        XCTAssertEqual(records[0].inputTokens, 12)
        XCTAssertEqual(records[0].outputTokens, 3)
        XCTAssertEqual(records[0].source, .providerReported)
    }

    func testGatewayServerOnlyAcceptsLocalToken() async throws {
        GatewayMockURLProtocol.configure { _ in (200, Data(#"{"usage":{"prompt_tokens":1,"completion_tokens":1}}"#.utf8)) }
        let usage = InMemoryUsageRecorder()
        let processor = GatewayProxyProcessor(
            upstream: GatewayUpstream(providerID: "acme", providerType: .openAICompatible, baseURL: try XCTUnwrap(URL(string: "https://upstream.example/v1")), keychainAccount: "provider.acme"),
            localToken: "local-token",
            keychain: GatewayKeychainDouble(values: ["provider.acme": "upstream-secret"]),
            usageRecorder: usage,
            session: mockSession()
        )
        let server = LocalGatewayServer()
        let status = try await server.start(processor: processor)
        defer { Task { await server.stop() } }
        var request = URLRequest(url: status.loopbackURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"model":"gpt-test"}"#.utf8)
        request.setValue("Bearer local-token", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        request.setValue("Bearer incorrect", forHTTPHeaderField: "Authorization")
        let (_, rejected) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode, 401)
    }

    func testSQLiteUsageRepositoryPersistsSanitizedMetrics() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "usage-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SQLiteUsageRepository(databaseURL: url)
        let record = GatewayUsageRecord(providerID: "acme", modelID: "gpt-test", latencyMilliseconds: 42, statusCode: 200, inputTokens: 10, outputTokens: 2, totalTokens: 12, source: .providerReported, errorCategory: nil)
        try await repository.record(record)
        let loaded = try await repository.recentUsage(limit: 1)
        let restored = try XCTUnwrap(loaded.first)
        XCTAssertEqual(restored.id, record.id)
        XCTAssertEqual(restored.providerID, "acme")
        XCTAssertEqual(restored.modelID, "gpt-test")
        XCTAssertEqual(restored.totalTokens, 12)
        XCTAssertEqual(restored.source, .providerReported)
        let summary = try await repository.summary(since: .distantPast)
        XCTAssertEqual(summary.requestCount, 1)
        XCTAssertEqual(summary.totalTokens, 12)
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatewayMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
