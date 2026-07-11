import CryptoKit
import Foundation
import Yams

public actor YAMLConfigurationStore {
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let backupRetention: Int

    public init(fileManager: FileManager = .default, backupRetention: Int = 10, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileManager = fileManager
        self.backupRetention = max(10, backupRetention)
        self.now = now
    }

    public func readDocument(at url: URL) throws -> (document: YAMLDocument, fingerprint: FileFingerprint) {
        guard fileManager.fileExists(atPath: url.path) else { throw AppError.configurationNotFound(url) }
        let data = try Data(contentsOf: url)
        do {
            let root = try YAMLDecoder().decode(YAMLValue.self, from: String(decoding: data, as: UTF8.self))
            return (YAMLDocument(root: root), try fingerprint(for: url, data: data))
        } catch { throw AppError.configurationParseFailed(error.localizedDescription) }
    }

    public func applyProvider(_ provider: ProviderConfiguration, at url: URL, expected: FileFingerprint) throws -> ConfigChangeResult {
        let current = try readDocument(at: url)
        guard current.fingerprint == expected else { throw AppError.configurationConflict(url) }
        let document = try updating(provider: provider, in: current.document)
        return try commit(document: document, to: url, expected: expected)
    }

    public func commit(document: YAMLDocument, to url: URL, expected: FileFingerprint) throws -> ConfigChangeResult {
        let data = try Data(contentsOf: url)
        let actual = try fingerprint(for: url, data: data)
        guard actual == expected else { throw AppError.configurationConflict(url) }
        let serialized: String
        do { serialized = try YAMLEncoder().encode(document.root) }
        catch { throw AppError.configurationWriteFailed(error.localizedDescription) }
        do { _ = try YAMLDecoder().decode(YAMLValue.self, from: serialized) }
        catch { throw AppError.configurationWriteFailed("Generated YAML did not parse: \(error.localizedDescription)") }
        let backupURL = try makeBackup(of: url)
        let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).omp-api-manager-\(UUID().uuidString).tmp")
        do {
            try Data(serialized.utf8).write(to: temporary, options: .withoutOverwriting)
            let latestData = try Data(contentsOf: url)
            guard try fingerprint(for: url, data: latestData) == expected else { throw AppError.configurationConflict(url) }
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: .usingNewMetadataOnly)
            let result = try readDocument(at: url)
            _ = try? pruneBackups(of: url, keeping: backupRetention)
            return ConfigChangeResult(changedURL: url, backupURL: backupURL, fingerprint: result.fingerprint)
        } catch let error as AppError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw AppError.configurationWriteFailed(error.localizedDescription)
        }
    }

    /// Restoring is a normal transaction: the current file is backed up before it is replaced.
    public func restoreBackup(_ backup: URL, to destination: URL, expected: FileFingerprint) throws -> ConfigChangeResult {
        let data = try Data(contentsOf: backup)
        do {
            let root = try YAMLDecoder().decode(YAMLValue.self, from: String(decoding: data, as: UTF8.self))
            return try commit(document: YAMLDocument(root: root), to: destination, expected: expected)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.configurationParseFailed("Backup \(backup.lastPathComponent): \(error.localizedDescription)")
        }
    }

    public func listBackups(of url: URL) throws -> [ConfigurationBackup] {
        let directory = url.deletingLastPathComponent()
        let prefix = "\(url.lastPathComponent).backup-"
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        return try contents.compactMap { candidate in
            guard candidate.lastPathComponent.hasPrefix(prefix) else { return nil }
            let values = try candidate.resourceValues(forKeys: [.contentModificationDateKey])
            return ConfigurationBackup(url: candidate, createdAt: values.contentModificationDate ?? .distantPast)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func pruneBackups(of url: URL, keeping count: Int = 10) throws -> [ConfigurationBackup] {
        let backups = try listBackups(of: url)
        let removed = Array(backups.dropFirst(max(10, count)))
        for backup in removed { try fileManager.removeItem(at: backup.url) }
        return removed
    }

    private func updating(provider: ProviderConfiguration, in document: YAMLDocument) throws -> YAMLDocument {
        guard case .object(var root) = document.root else { throw AppError.invalidProvider("models.yml root must be a mapping") }
        var providers: [String: YAMLValue]
        if case .object(let existing) = root["providers"] { providers = existing } else { providers = [:] }
        var providerObject: [String: YAMLValue]
        if case .object(let existing) = providers[provider.id] { providerObject = existing } else { providerObject = [:] }
        providerObject["baseUrl"] = .string(provider.baseURL.absoluteString)
        providerObject["apiKey"] = .string("!security find-generic-password -s com.omp-api-manager -a \(provider.keychainAccount) -w")
        providerObject["api"] = .string(provider.ompAPI)
        if !provider.headers.isEmpty { providerObject["headers"] = .object(provider.headers.mapValues(YAMLValue.string)) }
        providerObject["models"] = .array(provider.models.map { model in
            var modelObject: [String: YAMLValue] = ["id": .string(model.id), "name": .string(model.displayName)]
            if let value = model.contextWindow { modelObject["contextWindow"] = .integer(value) }
            if let value = model.maxTokens { modelObject["maxTokens"] = .integer(value) }
            if let values = model.inputModalities, !values.isEmpty { modelObject["input"] = .array(values.map(YAMLValue.string)) }
            if let value = model.supportsReasoning { modelObject["reasoning"] = .bool(value) }
            var cost: [String: YAMLValue] = [:]
            if let value = model.inputPricePerMillion { cost["input"] = .decimal(decimalDouble(value)) }
            if let value = model.outputPricePerMillion { cost["output"] = .decimal(decimalDouble(value)) }
            if let value = model.cacheReadPricePerMillion { cost["cacheRead"] = .decimal(decimalDouble(value)) }
            if let value = model.cacheWritePricePerMillion { cost["cacheWrite"] = .decimal(decimalDouble(value)) }
            if !cost.isEmpty { modelObject["cost"] = .object(cost) }
            return .object(modelObject)
        })
        providers[provider.id] = .object(providerObject)
        root["providers"] = .object(providers)
        return YAMLDocument(root: .object(root))
    }

    private func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func makeBackup(of url: URL) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: now()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appending(path: "\(url.lastPathComponent).backup-\(stamp)-\(UUID().uuidString.prefix(8))")
        do { try fileManager.copyItem(at: url, to: backup); return backup }
        catch { throw AppError.backupFailed(error.localizedDescription) }
    }

    private func fingerprint(for url: URL, data: Data) throws -> FileFingerprint {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return FileFingerprint(byteCount: data.count, modifiedAt: modifiedAt, digest: digest)
    }
}
