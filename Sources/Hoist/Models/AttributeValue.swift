import Foundation

/// A primitive value carried by user attributes, rule operands, and resolved flag values.
public enum AttributeValue: Sendable, Hashable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
}

extension AttributeValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AttributeValue must be a bool, int, double, or string"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):   try container.encode(value)
        case .int(let value):    try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

extension AttributeValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension AttributeValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension AttributeValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension AttributeValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

// MARK: - Typed accessors

extension AttributeValue {
    public var asBool: Bool? {
        if case .bool(let v) = self { return v } else { return nil }
    }
    public var asInt: Int? {
        switch self {
        case .int(let v):    return v
        case .double(let v): return Int(exactly: v)
        default:             return nil
        }
    }
    public var asDouble: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v):    return Double(v)
        default:             return nil
        }
    }
    public var asString: String? {
        if case .string(let v) = self { return v } else { return nil }
    }
}
