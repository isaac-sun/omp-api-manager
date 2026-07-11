import Foundation

public protocol SoftwareUpdateChecking: Sendable {
    func check(currentVersion: String) async throws -> SoftwareUpdateCheck
}

public actor GitHubSoftwareUpdateService: SoftwareUpdateChecking {
    private static let officialEndpoint = URL(string: "https://api.github.com/repos/isaac-sun/omp-api-manager/releases/latest")!
    private static let maximumResponseBytes = 1_048_576

    private let session: URLSession
    private let endpoint: URL
    private var cachedRelease: SoftwareRelease?
    private var entityTag: String?

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: GitHubUpdateRedirectDelegate(), delegateQueue: nil)
        endpoint = Self.officialEndpoint
    }

    init(session: URLSession, endpoint: URL = GitHubSoftwareUpdateService.officialEndpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    public func check(currentVersion: String) async throws -> SoftwareUpdateCheck {
        guard let current = SoftwareVersion(currentVersion) else { throw SoftwareUpdateError.invalidCurrentVersion }

        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("OMP-API-Manager/\(current.description) (https://github.com/isaac-sun/omp-api-manager)", forHTTPHeaderField: "User-Agent")
        if let entityTag { request.setValue(entityTag, forHTTPHeaderField: "If-None-Match") }

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw SoftwareUpdateError.invalidResponse }
            try validateResponseOrigin(http)

            switch http.statusCode {
            case 200:
                guard data.count <= Self.maximumResponseBytes else { throw SoftwareUpdateError.responseTooLarge }
                guard isJSON(http.value(forHTTPHeaderField: "Content-Type")) else { throw SoftwareUpdateError.invalidResponse }
                let release = try decodeRelease(data)
                cachedRelease = release
                entityTag = validEntityTag(http.value(forHTTPHeaderField: "ETag"))
                return SoftwareUpdateCheck(currentVersion: current, latestRelease: release)
            case 304:
                guard let cachedRelease else { throw SoftwareUpdateError.invalidResponse }
                return SoftwareUpdateCheck(currentVersion: current, latestRelease: cachedRelease)
            case 403, 429:
                throw SoftwareUpdateError.rateLimited(retryAfter: retryDate(from: http))
            case 404:
                throw SoftwareUpdateError.noPublishedRelease
            default:
                throw SoftwareUpdateError.unexpectedHTTPStatus(http.statusCode)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }

    private func decodeRelease(_ data: Data) throws -> SoftwareRelease {
        let payload: GitHubReleasePayload
        do { payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data) }
        catch { throw SoftwareUpdateError.invalidResponse }

        guard !payload.draft,
              !payload.prerelease,
              payload.tagName.first == "v",
              let version = SoftwareVersion(payload.tagName),
              version.isStable,
              payload.tagName == "v\(version.description)",
              let officialURL = URL(string: "https://github.com/isaac-sun/omp-api-manager/releases/tag/\(payload.tagName)") else {
            throw SoftwareUpdateError.invalidResponse
        }

        let title = sanitized(payload.name?.isEmpty == false ? payload.name! : payload.tagName, maximumLength: 200)
        let notes = sanitized(payload.body ?? "", maximumLength: 20_000)
        let publishedAt = payload.publishedAt.flatMap(parseISO8601Date)
        return SoftwareRelease(version: version, tagName: payload.tagName, title: title, notes: notes, publishedAt: publishedAt, officialReleaseURL: officialURL)
    }

    private func validateResponseOrigin(_ response: HTTPURLResponse) throws {
        guard let responseURL = response.url,
              responseURL.scheme?.lowercased() == "https",
              responseURL.host?.lowercased() == endpoint.host?.lowercased(),
              responseURL.port == nil,
              responseURL.user == nil,
              responseURL.password == nil,
              responseURL.path == endpoint.path else { throw SoftwareUpdateError.untrustedResponse }
    }

    private func isJSON(_ contentType: String?) -> Bool {
        guard let contentType = contentType?.lowercased() else { return false }
        return contentType.contains("application/json") || contentType.contains("application/vnd.github+json")
    }

    private func validEntityTag(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.utf8.count <= 256,
              value.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }) else { return nil }
        return value
    }

    private func retryDate(from response: HTTPURLResponse) -> Date? {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(retryAfter) {
            return Date().addingTimeInterval(max(0, seconds))
        }
        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"), let seconds = TimeInterval(reset) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private func sanitized(_ value: String, maximumLength: Int) -> String {
        let filtered = value.unicodeScalars.filter { scalar in
            scalar.value == 9 || scalar.value == 10 || scalar.value == 13 || scalar.value >= 32
        }
        return String(String.UnicodeScalarView(filtered).prefix(maximumLength))
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease
        case publishedAt = "published_at"
    }
}

private final class GitHubUpdateRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "api.github.com",
              url.port == nil,
              url.user == nil,
              url.password == nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
