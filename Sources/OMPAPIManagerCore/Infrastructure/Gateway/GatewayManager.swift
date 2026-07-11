import Foundation

/// Owns one explicitly selected loopback Gateway instance. It never opens a public listener.
public actor GatewayManager {
    private let server: LocalGatewayServer
    private let usageRepository: any UsageRecording
    private let keychain: any SecretStoring
    private let tokenService: GatewayAccessTokenService

    public init(server: LocalGatewayServer = LocalGatewayServer(), usageRepository: any UsageRecording, keychain: any SecretStoring = KeychainService()) {
        self.server = server
        self.usageRepository = usageRepository
        self.keychain = keychain
        self.tokenService = GatewayAccessTokenService(keychain: keychain)
    }

    public func start(for provider: ProviderConfiguration, port: Int = 0) async throws -> GatewayStatus {
        let token = try tokenService.loadOrCreate()
        let upstream = GatewayUpstream(providerID: provider.id, providerType: provider.type, baseURL: provider.baseURL, keychainAccount: provider.keychainAccount)
        let processor = GatewayProxyProcessor(upstream: upstream, localToken: token, keychain: keychain, usageRecorder: usageRepository)
        return try await server.start(processor: processor, port: port)
    }

    public func stop() async { await server.stop() }
    public func status() async -> GatewayStatus? { await server.currentStatus() }
}
