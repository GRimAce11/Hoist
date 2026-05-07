import Foundation

/// A single attribute predicate, e.g. `country == "US"` or `appBuild >= 4200`.
public struct Condition: Sendable, Equatable {
    public let attribute: String
    public let `operator`: ConditionOperator

    public init(attribute: String, operator op: ConditionOperator) {
        self.attribute = attribute
        self.operator = op
    }
}

/// The supported operators for matching a context attribute against a value.
public enum ConditionOperator: Sendable, Equatable {
    case eq(AttributeValue)
    case neq(AttributeValue)
    case `in`([AttributeValue])
    case notIn([AttributeValue])
    case gt(AttributeValue)
    case gte(AttributeValue)
    case lt(AttributeValue)
    case lte(AttributeValue)
    case contains(String)
    case startsWith(String)
    case endsWith(String)
}

extension ConditionOperator {
    /// Decodes an operator from one of:
    ///   - a primitive value (sugar for `.eq`): `"US"`, `42`, `true`
    ///   - an object with a single operator key: `{ "in": ["US", "CA"] }`, `{ "gte": 18 }`
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try the primitive sugar first (implicit equality).
        if let primitive = try? container.decode(AttributeValue.self) {
            self = .eq(primitive)
            return
        }

        // Otherwise expect an object with exactly one operator key.
        let keyed = try decoder.container(keyedBy: OperatorKey.self)
        guard let key = keyed.allKeys.first, keyed.allKeys.count == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: OperatorKey.eq,
                in: keyed,
                debugDescription: "Operator object must have exactly one key (eq, neq, in, notIn, gt, gte, lt, lte, contains, startsWith, endsWith)."
            )
        }

        switch key {
        case .eq:         self = .eq(try keyed.decode(AttributeValue.self, forKey: key))
        case .neq:        self = .neq(try keyed.decode(AttributeValue.self, forKey: key))
        case .`in`:       self = .in(try keyed.decode([AttributeValue].self, forKey: key))
        case .notIn:      self = .notIn(try keyed.decode([AttributeValue].self, forKey: key))
        case .gt:         self = .gt(try keyed.decode(AttributeValue.self, forKey: key))
        case .gte:        self = .gte(try keyed.decode(AttributeValue.self, forKey: key))
        case .lt:         self = .lt(try keyed.decode(AttributeValue.self, forKey: key))
        case .lte:        self = .lte(try keyed.decode(AttributeValue.self, forKey: key))
        case .contains:   self = .contains(try keyed.decode(String.self, forKey: key))
        case .startsWith: self = .startsWith(try keyed.decode(String.self, forKey: key))
        case .endsWith:   self = .endsWith(try keyed.decode(String.self, forKey: key))
        }
    }

    private enum OperatorKey: String, CodingKey {
        case eq, neq
        case `in`, notIn
        case gt, gte, lt, lte
        case contains, startsWith, endsWith
    }
}
