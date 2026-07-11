import Foundation

enum GatewayUsageExtractor {
    static func modelID(from body: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["model"] as? String
    }

    static func usage(from body: Data, providerType: ProviderType) -> (input: Int, output: Int, total: Int)? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else { return nil }
        let inputKey = providerType == .anthropicCompatible || providerType == .customAnthropicLike ? "input_tokens" : "prompt_tokens"
        let outputKey = providerType == .anthropicCompatible || providerType == .customAnthropicLike ? "output_tokens" : "completion_tokens"
        guard let input = number(usage[inputKey]), let output = number(usage[outputKey]) else { return nil }
        return (input, output, number(usage["total_tokens"]) ?? input + output)
    }

    private static func number(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
