import Foundation

public protocol ProviderRepository: Sendable {
    func fetchAll() async throws -> [ProviderConfiguration]
    func upsert(_ provider: ProviderConfiguration) async throws
    func delete(id: String) async throws
}
