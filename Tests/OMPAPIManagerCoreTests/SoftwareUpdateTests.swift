import Foundation
import XCTest
@testable import OMPAPIManagerCore

private final class UpdateMockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let responseURL: URL?

        init(statusCode: Int, headers: [String: String] = ["Content-Type": "application/json"], body: Data = Data(), responseURL: URL? = nil) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.responseURL = responseURL
        }
    }

    typealias Handler = @Sendable (URLRequest) throws -> Stub
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        do {
            guard let handler else { throw URLError(.badServerResponse) }
            let stub = try handler(request)
            let url = stub.responseURL ?? request.url!
            let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !stub.body.isEmpty { client?.urlProtocol(self, didLoad: stub.body) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset(handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        capturedRequests = []
        lock.unlock()
    }

    static func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }
}

final class SoftwareVersionTests: XCTestCase {
    func testParsesAndOrdersSemanticVersions() throws {
        XCTAssertEqual(try XCTUnwrap(SoftwareVersion("v0.3.0")).description, "0.3.0")
        XCTAssertLessThan(try XCTUnwrap(SoftwareVersion("0.3.0-beta.1")), try XCTUnwrap(SoftwareVersion("0.3.0")))
        XCTAssertLessThan(try XCTUnwrap(SoftwareVersion("1.0.0-alpha")), try XCTUnwrap(SoftwareVersion("1.0.0-alpha.1")))
        XCTAssertLessThan(try XCTUnwrap(SoftwareVersion("1.0.0-1")), try XCTUnwrap(SoftwareVersion("1.0.0-alpha")))
        XCTAssertEqual(SoftwareVersion("1.2.3+45"), SoftwareVersion("1.2.3+99"))
    }

    func testRejectsInvalidSemanticVersions() {
        XCTAssertNil(SoftwareVersion("1.2"))
        XCTAssertNil(SoftwareVersion("1.2.3.4"))
        XCTAssertNil(SoftwareVersion("1.02.3"))
        XCTAssertNil(SoftwareVersion("1.2.3-"))
        XCTAssertNil(SoftwareVersion("1.2.3-rc.01"))
    }
}

final class SoftwareUpdateServiceTests: XCTestCase {
    override func tearDown() {
        UpdateMockURLProtocol.reset { _ in UpdateMockURLProtocol.Stub(statusCode: 500) }
        super.tearDown()
    }

    func testFindsUpdateAndSendsOnlyPublicGitHubHeaders() async throws {
        UpdateMockURLProtocol.reset { _ in
            UpdateMockURLProtocol.Stub(
                statusCode: 200,
                headers: ["Content-Type": "application/json; charset=utf-8", "ETag": #"W/"release-030""#],
                body: Self.releaseJSON(tag: "v0.3.0")
            )
        }
        let service = GitHubSoftwareUpdateService(session: mockSession())

        let result = try await service.check(currentVersion: "0.2.0")

        XCTAssertTrue(result.isUpdateAvailable)
        XCTAssertEqual(result.latestRelease.version, SoftwareVersion("0.3.0"))
        XCTAssertEqual(result.latestRelease.officialReleaseURL.absoluteString, "https://github.com/isaac-sun/omp-api-manager/releases/tag/v0.3.0")
        let request = try XCTUnwrap(UpdateMockURLProtocol.requests().first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/isaac-sun/omp-api-manager/releases/latest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertTrue(try XCTUnwrap(request.value(forHTTPHeaderField: "User-Agent")).contains("0.2.0"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testUsesETagAndCachedReleaseForNotModifiedResponse() async throws {
        UpdateMockURLProtocol.reset { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == #"W/"release-030""# {
                return UpdateMockURLProtocol.Stub(statusCode: 304, headers: [:])
            }
            return UpdateMockURLProtocol.Stub(
                statusCode: 200,
                headers: ["Content-Type": "application/json", "ETag": #"W/"release-030""#],
                body: Self.releaseJSON(tag: "v0.3.0")
            )
        }
        let service = GitHubSoftwareUpdateService(session: mockSession())

        let first = try await service.check(currentVersion: "0.2.0")
        let second = try await service.check(currentVersion: "0.2.0")

        XCTAssertEqual(first, second)
        XCTAssertEqual(UpdateMockURLProtocol.requests().count, 2)
        XCTAssertEqual(UpdateMockURLProtocol.requests().last?.value(forHTTPHeaderField: "If-None-Match"), #"W/"release-030""#)
    }

    func testDistinguishesCurrentAndNewerDevelopmentVersions() async throws {
        UpdateMockURLProtocol.reset { _ in UpdateMockURLProtocol.Stub(statusCode: 200, body: Self.releaseJSON(tag: "v0.3.0")) }
        let currentService = GitHubSoftwareUpdateService(session: mockSession())
        let current = try await currentService.check(currentVersion: "0.3.0")
        XCTAssertFalse(current.isUpdateAvailable)
        XCTAssertEqual(current.currentVersion, current.latestRelease.version)

        let developmentService = GitHubSoftwareUpdateService(session: mockSession())
        let development = try await developmentService.check(currentVersion: "0.4.0-beta.1")
        XCTAssertFalse(development.isUpdateAvailable)
        XCTAssertGreaterThan(development.currentVersion, development.latestRelease.version)
    }

    func testRejectsUntrustedResponseOrigin() async throws {
        UpdateMockURLProtocol.reset { _ in
            UpdateMockURLProtocol.Stub(
                statusCode: 200,
                body: Self.releaseJSON(tag: "v0.3.0"),
                responseURL: URL(string: "https://example.com/releases/latest")!
            )
        }
        let service = GitHubSoftwareUpdateService(session: mockSession())

        do {
            _ = try await service.check(currentVersion: "0.2.0")
            XCTFail("Expected an untrusted response error")
        } catch let error as SoftwareUpdateError {
            XCTAssertEqual(error, .untrustedResponse)
        }
    }

    func testRejectsPrereleasePayloadAndMapsRateLimit() async throws {
        UpdateMockURLProtocol.reset { _ in UpdateMockURLProtocol.Stub(statusCode: 200, body: Self.releaseJSON(tag: "v0.3.0", prerelease: true)) }
        let prereleaseService = GitHubSoftwareUpdateService(session: mockSession())
        do {
            _ = try await prereleaseService.check(currentVersion: "0.2.0")
            XCTFail("Expected an invalid response")
        } catch let error as SoftwareUpdateError {
            XCTAssertEqual(error, .invalidResponse)
        }

        UpdateMockURLProtocol.reset { _ in UpdateMockURLProtocol.Stub(statusCode: 429, headers: ["Retry-After": "60"]) }
        let limitedService = GitHubSoftwareUpdateService(session: mockSession())
        do {
            _ = try await limitedService.check(currentVersion: "0.2.0")
            XCTFail("Expected rate limiting")
        } catch let error as SoftwareUpdateError {
            guard case .rateLimited(let retryAfter) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertNotNil(retryAfter)
        }
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func releaseJSON(tag: String, prerelease: Bool = false) -> Data {
        Data(#"{"tag_name":"\#(tag)","name":"OMP API Manager \#(tag)","body":"Release notes","draft":false,"prerelease":\#(prerelease),"published_at":"2026-07-11T12:00:00Z","html_url":"https://example.invalid/untrusted"}"#.utf8)
    }
}
