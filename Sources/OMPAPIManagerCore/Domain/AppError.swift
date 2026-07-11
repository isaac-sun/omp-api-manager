import Foundation
import Security

public enum AppError: Error, LocalizedError, Sendable, Equatable {
    case ompNotInstalled
    case unsupportedOMPVersion(String)
    case configurationNotFound(URL)
    case configurationParseFailed(String)
    case configurationConflict(URL)
    case configurationWriteFailed(String)
    case backupFailed(String)
    case keychainFailed(OSStatus)
    case gatewayStartFailed
    case endpointUnreachable(String)
    case modelUnavailable(String)
    case invalidEndpoint(String)
    case invalidProvider(String)
    case databaseError

    public var errorDescription: String? {
        switch self {
        case .ompNotInstalled: "OMP is not installed. You can still save provider drafts."
        case .unsupportedOMPVersion(let version): "OMP \(version) is not supported for writes."
        case .configurationNotFound(let url): "Configuration was not found at \(url.path)."
        case .configurationParseFailed(let details): "The configuration is not valid YAML: \(details)"
        case .configurationConflict(let url): "The configuration changed outside OMP API Manager: \(url.lastPathComponent)."
        case .configurationWriteFailed(let details): "Could not safely write configuration: \(details)"
        case .backupFailed(let details): "Could not create a configuration backup: \(details)"
        case .keychainFailed: "Could not access the macOS Keychain."
        case .gatewayStartFailed: "Could not start the local Gateway."
        case .endpointUnreachable(let details): "Endpoint is unreachable: \(details)"
        case .modelUnavailable(let id): "Model is unavailable: \(id)"
        case .invalidEndpoint(let endpoint): "Invalid API base URL: \(endpoint)"
        case .invalidProvider(let reason): "Invalid provider: \(reason)"
        case .databaseError: "Could not safely read or write local provider metadata."
        }
    }
}

public enum ProviderConnectionError: Error, LocalizedError, Sendable, Equatable {
    case invalidAPIKey(statusCode: Int?)
    case permissionDenied(statusCode: Int?)
    case endpointUnreachable(String)
    case tlsError(String)
    case requestTimedOut
    case rateLimited(statusCode: Int?)
    case modelNotFound(statusCode: Int?)
    case malformedResponse
    case serverError(statusCode: Int?)
    case unexpectedHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey: "Authentication failed. Check the API key."
        case .permissionDenied: "The API key does not have permission for this operation."
        case .endpointUnreachable(let detail): "The provider endpoint could not be reached: \(detail)"
        case .tlsError(let detail): "The TLS connection could not be verified: \(detail)"
        case .requestTimedOut: "The provider request timed out."
        case .rateLimited: "The provider rate-limited this request."
        case .modelNotFound: "The selected model was not found or is not available."
        case .malformedResponse: "The provider returned an unexpected response."
        case .serverError: "The provider returned a server error."
        case .unexpectedHTTPStatus(let status): "The provider returned HTTP \(status)."
        }
    }
}
