import Foundation
import Security

public protocol SecretStoring: Sendable {
    func save(secret: String, account: String) throws
    func read(account: String) throws -> String
    func delete(account: String) throws
}

public final class KeychainService: SecretStoring, @unchecked Sendable {
    public static let service = "com.omp-api-manager"
    public init() {}

    public func save(secret: String, account: String) throws {
        try? delete(account: account)
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: account, kSecValueData: Data(secret.utf8), kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppError.keychainFailed(status) }
    }

    public func read(account: String) throws -> String {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let secret = String(data: data, encoding: .utf8) else { throw AppError.keychainFailed(status) }
        return secret
    }

    public func delete(account: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.keychainFailed(status) }
    }
}
