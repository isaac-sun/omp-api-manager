import Foundation

/// Imports the JSON connection format emitted by New API-compatible channel tools.
/// The source payload is decoded only in memory; its key is never persisted outside Keychain.
public struct NewAPIChannelConnectionImporter: Sendable {
    public init() {}

    public func decode(_ source: String, existingProviderIDs: Set<String>) throws -> (provider: ProviderConfiguration, apiKey: String) {
        struct Payload: Decodable {
            let type: String
            let key: String
            let url: String

            enum CodingKeys: String, CodingKey {
                case type = "_type"
                case key
                case url
            }
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(source.utf8))
        } catch {
            throw AppError.invalidProvider("The connection must be valid newapi_channel_conn JSON.")
        }
        guard payload.type == "newapi_channel_conn" else {
            throw AppError.invalidProvider("Unsupported connection type. Expected newapi_channel_conn.")
        }
        guard !payload.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidProvider("The connection does not contain an API key.")
        }
        guard let endpoint = URL(string: payload.url) else {
            throw AppError.invalidEndpoint("The connection does not contain a valid URL.")
        }

        let baseURL = normalizedOpenAIBaseURL(endpoint)
        let identifier = uniqueIdentifier(for: baseURL, existingProviderIDs: existingProviderIDs)
        let host = baseURL.host ?? "endpoint"
        let provider = ProviderConfiguration(
            id: identifier,
            displayName: "New API · \(host)",
            type: .customOpenAILike,
            baseURL: baseURL,
            keychainAccount: "provider.\(identifier)",
            tags: ["newapi"]
        )
        return (provider, payload.key)
    }

    private func normalizedOpenAIBaseURL(_ endpoint: URL) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.path.isEmpty || components.path == "/" else {
            return endpoint
        }
        components.path = "/v1"
        return components.url ?? endpoint
    }

    private func uniqueIdentifier(for endpoint: URL, existingProviderIDs: Set<String>) -> String {
        let host = endpoint.host?.lowercased() ?? "endpoint"
        let parts = host.split(separator: ".").filter { $0 != "www" }.map(String.init)
        let base = "newapi-" + parts.joined(separator: "-")
        let sanitized = base.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        let preferred = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard existingProviderIDs.contains(preferred) else { return preferred }
        var suffix = 2
        while existingProviderIDs.contains("\(preferred)-\(suffix)") { suffix += 1 }
        return "\(preferred)-\(suffix)"
    }
}
