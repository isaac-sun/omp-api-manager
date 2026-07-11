import Foundation
import XCTest
@testable import OMPAPIManagerCore

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (statusCode: Int, body: Data)
    nonisolated(unsafe) static var handler: Handler?
    private static let lock = NSLock()
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.badServerResponse) }
            let response = try handler(request)
            let http = HTTPURLResponse(url: request.url!, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset(handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        requests = []
        lock.unlock()
    }
}

final class ProviderAdapterTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset { _ in (500, Data()) }
        super.tearDown()
    }

    func testOpenAIAdapterFetchesModelsAndTestsSelectedModel() async throws {
        MockURLProtocol.reset { request in
            switch request.url?.path {
            case "/v1/models":
                return (200, Data(#"{"data":[{"id":"gpt-test"}]}"#.utf8))
            case "/v1/chat/completions":
                return (200, Data(#"{"id":"chatcmpl-test"}"#.utf8))
            default: return (404, Data())
            }
        }
        let adapter = OpenAICompatibleAdapter(session: mockSession())
        let credentials = ProviderCredentials(baseURL: try XCTUnwrap(URL(string: "https://mock.example/v1")), apiKey: "fake-key")
        let models = try await adapter.fetchModels(credentials: credentials)
        XCTAssertEqual(models.map(\.id), ["gpt-test"])
        let result = try await adapter.testConnection(credentials: credentials, model: "gpt-test")
        XCTAssertEqual(result.statusCode, 200)
        let requests = MockURLProtocol.requests
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fake-key")
        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertEqual(requests[1].url?.path, "/v1/chat/completions")
    }

    func testAnthropicAdapterUsesMessagesProtocol() async throws {
        MockURLProtocol.reset { request in
            switch request.url?.path {
            case "/v1/models":
                return (200, Data(#"{"data":[{"id":"claude-test","display_name":"Claude Test"}]}"#.utf8))
            case "/v1/messages":
                return (200, Data(#"{"id":"msg_test"}"#.utf8))
            default: return (404, Data())
            }
        }
        let adapter = AnthropicCompatibleAdapter(session: mockSession())
        let credentials = ProviderCredentials(baseURL: try XCTUnwrap(URL(string: "https://mock.example/v1")), apiKey: "fake-key")
        let models = try await adapter.fetchModels(credentials: credentials)
        XCTAssertEqual(models.first?.displayName, "Claude Test")
        _ = try await adapter.testConnection(credentials: credentials, model: "claude-test")
        let request = try XCTUnwrap(MockURLProtocol.requests.last)
        XCTAssertEqual(request.url?.path, "/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fake-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testHTTPAuthenticationFailureIsClassified() async throws {
        MockURLProtocol.reset { _ in (401, Data(#"{"error":"invalid"}"#.utf8)) }
        let adapter = OpenAICompatibleAdapter(session: mockSession())
        let credentials = ProviderCredentials(baseURL: try XCTUnwrap(URL(string: "https://mock.example/v1")), apiKey: "fake-key")
        do {
            _ = try await adapter.fetchModels(credentials: credentials)
            XCTFail("Expected an authentication error")
        } catch let error as ProviderConnectionError {
            XCTAssertEqual(error, .invalidAPIKey(statusCode: 401))
        }
    }

    func testErrorMapperClassifiesProviderFailures() {
        XCTAssertEqual(ProviderHTTPErrorMapper.from(statusCode: 403), .permissionDenied(statusCode: 403))
        XCTAssertEqual(ProviderHTTPErrorMapper.from(statusCode: 404), .modelNotFound(statusCode: 404))
        XCTAssertEqual(ProviderHTTPErrorMapper.from(statusCode: 429), .rateLimited(statusCode: 429))
        XCTAssertEqual(ProviderHTTPErrorMapper.from(statusCode: 503), .serverError(statusCode: 503))
        XCTAssertEqual(ProviderHTTPErrorMapper.map(URLError(.timedOut)) as? ProviderConnectionError, .requestTimedOut)
        XCTAssertEqual(ProviderHTTPErrorMapper.map(URLError(.secureConnectionFailed)) as? ProviderConnectionError, .tlsError(URLError(.secureConnectionFailed).localizedDescription))
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
