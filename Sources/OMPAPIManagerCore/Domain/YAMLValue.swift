import Foundation

/// A YAML-compatible value tree. Unknown keys are retained during a targeted mutation.
public indirect enum YAMLValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case decimal(Double)
    case string(String)
    case array([YAMLValue])
    case object([String: YAMLValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .decimal(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([YAMLValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: YAMLValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .decimal(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public struct YAMLDocument: Sendable, Equatable {
    public var root: YAMLValue
    public init(root: YAMLValue) { self.root = root }
}
