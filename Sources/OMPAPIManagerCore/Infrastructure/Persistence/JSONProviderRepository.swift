import Foundation

/// Local provider metadata store. API key values are intentionally excluded and live only in Keychain.
public actor JSONProviderRepository: ProviderRepository {
    private let storageURL: URL
    private let fileManager: FileManager

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    public static func applicationSupportDefault() throws -> JSONProviderRepository {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppError.databaseError
        }
        return JSONProviderRepository(storageURL: directory.appending(path: "OMP API Manager/providers.json"))
    }

    public func fetchAll() throws -> [ProviderConfiguration] {
        guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ProviderConfiguration].self, from: data)
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch { throw AppError.databaseError }
    }

    public func upsert(_ provider: ProviderConfiguration) throws {
        var providers = try fetchAll()
        var updated = provider
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            updated.createdAt = providers[index].createdAt
            updated.updatedAt = .now
            providers[index] = updated
        } else {
            providers.append(updated)
        }
        try write(providers)
    }

    public func delete(id: String) throws {
        var providers = try fetchAll()
        providers.removeAll { $0.id == id }
        try write(providers)
    }

    private func write(_ providers: [ProviderConfiguration]) throws {
        do {
            try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(providers).write(to: storageURL, options: .atomic)
        } catch { throw AppError.databaseError }
    }
}
