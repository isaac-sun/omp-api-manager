import Foundation
import Yams

public struct SanitizedYAMLDocument: Sendable, Equatable {
    public let text: String
    public let fingerprint: FileFingerprint

    public init(text: String, fingerprint: FileFingerprint) {
        self.text = text
        self.fingerprint = fingerprint
    }
}

/// Advanced editor support for `models.yml`. It never returns existing secret values to the UI.
public struct ModelsYAMLEditingService: Sendable {
    public static let redactedSecretMarker = "__OMP_API_MANAGER_REDACTED__"
    private let store: YAMLConfigurationStore

    public init(store: YAMLConfigurationStore = YAMLConfigurationStore()) {
        self.store = store
    }

    public func load(at url: URL) async throws -> SanitizedYAMLDocument {
        let current = try await store.readDocument(at: url)
        let sanitized = redactSecrets(in: current.document.root)
        do {
            return SanitizedYAMLDocument(text: try YAMLEncoder().encode(sanitized), fingerprint: current.fingerprint)
        } catch {
            throw AppError.configurationWriteFailed("Could not serialize sanitized YAML: \(error.localizedDescription)")
        }
    }

    /// Applies parsed YAML only after restoring redacted values from the fresh on-disk document.
    public func save(editedYAML: String, to url: URL, expected: FileFingerprint) async throws -> ConfigChangeResult {
        let edited: YAMLValue
        do { edited = try YAMLDecoder().decode(YAMLValue.self, from: editedYAML) }
        catch { throw AppError.configurationParseFailed(error.localizedDescription) }
        let current = try await store.readDocument(at: url)
        guard current.fingerprint == expected else { throw AppError.configurationConflict(url) }
        try validateEditedSecretValues(in: edited)
        let merged = restoreRedactedValues(in: edited, from: current.document.root)
        return try await store.commit(document: YAMLDocument(root: merged), to: url, expected: expected)
    }

    public func copyProvider(_ provider: ProviderConfiguration, to url: URL, expected: FileFingerprint) async throws -> ConfigChangeResult {
        try await store.applyProvider(provider, at: url, expected: expected)
    }

    private func redactSecrets(in value: YAMLValue, key: String? = nil) -> YAMLValue {
        switch value {
        case .object(let object):
            var sanitized: [String: YAMLValue] = [:]
            for (childKey, child) in object {
                sanitized[childKey] = redactSecrets(in: child, key: childKey)
            }
            return .object(sanitized)
        case .array(let array):
            return .array(array.map { redactSecrets(in: $0) })
        case .string where key.map(isSecretKey) == true:
            return .string(Self.redactedSecretMarker)
        default:
            return value
        }
    }

    private func restoreRedactedValues(in edited: YAMLValue, from original: YAMLValue, key: String? = nil) -> YAMLValue {
        if case .string(let text) = edited, text == Self.redactedSecretMarker, isSecretKey(key ?? "") {
            return original
        }
        switch (edited, original) {
        case (.object(let editedObject), .object(let originalObject)):
            var restored: [String: YAMLValue] = [:]
            for (childKey, child) in editedObject {
                restored[childKey] = restoreRedactedValues(in: child, from: originalObject[childKey] ?? .null, key: childKey)
            }
            return .object(restored)
        case (.array(let editedArray), .array(let originalArray)):
            return .array(editedArray.enumerated().map { index, child in
                restoreRedactedValues(in: child, from: originalArray.indices.contains(index) ? originalArray[index] : .null, key: key)
            })
        default:
            return edited
        }
    }

    /// The marker can preserve a legacy on-disk secret without ever returning it to the UI.
    /// Any non-marker secret introduced by the user must be a command reference.
    private func validateEditedSecretValues(in value: YAMLValue, key: String? = nil) throws {
        switch value {
        case .object(let object):
            for (childKey, child) in object { try validateEditedSecretValues(in: child, key: childKey) }
        case .array(let array):
            for child in array { try validateEditedSecretValues(in: child, key: key) }
        case .string(let string) where isSecretKey(key ?? ""):
            guard string == Self.redactedSecretMarker || string.hasPrefix("!") else {
                throw AppError.invalidProvider("\(key ?? "Secret") must be a Keychain or other command reference beginning with !; plaintext secrets are not accepted.")
            }
        default:
            break
        }
    }

    private func isSecretKey(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        return ["apikey", "authorization", "token", "secret", "password"].contains { normalized.contains($0) }
    }
}
