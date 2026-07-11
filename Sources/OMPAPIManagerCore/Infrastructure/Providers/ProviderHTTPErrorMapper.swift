import Foundation

enum ProviderHTTPErrorMapper {
    static func validate(_ response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw ProviderConnectionError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw from(statusCode: http.statusCode) }
        return http
    }

    static func from(statusCode: Int) -> ProviderConnectionError {
        switch statusCode {
        case 401: .invalidAPIKey(statusCode: statusCode)
        case 403: .permissionDenied(statusCode: statusCode)
        case 404: .modelNotFound(statusCode: statusCode)
        case 408, 504: .requestTimedOut
        case 429: .rateLimited(statusCode: statusCode)
        case 500...599: .serverError(statusCode: statusCode)
        default: .unexpectedHTTPStatus(statusCode)
        }
    }

    static func map(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .timedOut: return ProviderConnectionError.requestTimedOut
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired:
            return ProviderConnectionError.tlsError(urlError.localizedDescription)
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet, .networkConnectionLost:
            return ProviderConnectionError.endpointUnreachable(urlError.localizedDescription)
        default: return ProviderConnectionError.endpointUnreachable(urlError.localizedDescription)
        }
    }
}
