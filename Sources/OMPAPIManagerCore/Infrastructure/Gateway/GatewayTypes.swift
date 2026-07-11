import Foundation
import Security

public struct GatewayUpstream: Sendable, Equatable {
    public let providerID: String
    public let providerType: ProviderType
    public let baseURL: URL
    public let keychainAccount: String

    public init(providerID: String, providerType: ProviderType, baseURL: URL, keychainAccount: String) {
        self.providerID = providerID
        self.providerType = providerType
        self.baseURL = baseURL
        self.keychainAccount = keychainAccount
    }
}

public struct GatewayRequest: Sendable {
    public let method: String
    public let target: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, target: String, headers: [String: String], body: Data) {
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
    }
}

public struct GatewayResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public struct GatewayResponseHead: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public init(statusCode: Int, headers: [String: String]) { self.statusCode = statusCode; self.headers = headers }
}

public struct GatewayStatus: Sendable, Equatable {
    public let port: Int
    public let startedAt: Date
    public init(port: Int, startedAt: Date = .now) { self.port = port; self.startedAt = startedAt }
    public var loopbackURL: URL { URL(string: "http://127.0.0.1:\(port)")! }
}

public enum GatewayAuthorizationError: Error, LocalizedError, Sendable {
    case missingOrInvalidToken

    public var errorDescription: String? { "The local Gateway token is missing or invalid." }
}

public final class GatewayAccessTokenService: @unchecked Sendable {
    public static let account = "gateway.local-token"
    private let keychain: any SecretStoring

    public init(keychain: any SecretStoring = KeychainService()) { self.keychain = keychain }

    public func loadOrCreate() throws -> String {
        if let existing = try? keychain.read(account: Self.account), !existing.isEmpty { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppError.keychainFailed(errSecInternalError) }
        let token = Data(bytes).base64EncodedString()
        try keychain.save(secret: token, account: Self.account)
        return token
    }
}
