import Foundation

/// A single rule in a flag's `rules` array. Evaluated top-to-bottom; first match wins.
public enum Rule: Sendable, Equatable {
    /// All conditions must match (AND). Returns `value` on match.
    case condition(conditions: [Condition], value: AttributeValue)

    /// Returns `value` if `hash(flagKey + userID) % 100 < percentage`.
    case rollout(percentage: Int, value: AttributeValue)

    /// Deterministically picks one variant by weight. Variant string becomes the value.
    /// Only meaningful for string flags.
    case split(variants: [SplitVariant])
}

/// One bucket in a `split` rule.
public struct SplitVariant: Sendable, Equatable, Codable {
    public let value: String
    public let weight: Int

    public init(value: String, weight: Int) {
        self.value = value
        self.weight = weight
    }
}

extension Rule: Decodable {
    private enum CodingKeys: String, CodingKey {
        case `if`
        case rollout
        case split
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 1. Split rule
        if container.contains(.split) {
            let weights = try container.decode([String: Int].self, forKey: .split)
            let variants = weights
                .map { SplitVariant(value: $0.key, weight: $0.value) }
                .sorted { $0.value < $1.value }   // stable iteration order
            guard !variants.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .split, in: container,
                    debugDescription: "split rule must contain at least one variant"
                )
            }
            guard variants.allSatisfy({ $0.weight >= 0 }) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .split, in: container,
                    debugDescription: "split weights must be non-negative"
                )
            }
            self = .split(variants: variants)
            return
        }

        // 2. Rollout rule
        if container.contains(.rollout) {
            let percentage = try container.decode(Int.self, forKey: .rollout)
            guard (0...100).contains(percentage) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .rollout, in: container,
                    debugDescription: "rollout percentage must be in 0...100"
                )
            }
            let value = try container.decode(AttributeValue.self, forKey: .value)
            self = .rollout(percentage: percentage, value: value)
            return
        }

        // 3. Condition rule
        if container.contains(.if) {
            let predicates = try container.decode([String: ConditionOperatorBox].self, forKey: .if)
            let conditions = predicates
                .map { Condition(attribute: $0.key, operator: $0.value.value) }
                .sorted { $0.attribute < $1.attribute }   // stable order for tests
            let value = try container.decode(AttributeValue.self, forKey: .value)
            self = .condition(conditions: conditions, value: value)
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .if, in: container,
            debugDescription: "Rule must contain one of: 'if', 'rollout', 'split'"
        )
    }
}

/// Wrapper to invoke `ConditionOperator`'s custom decoder when used as a dictionary value.
private struct ConditionOperatorBox: Decodable {
    let value: ConditionOperator
    init(from decoder: Decoder) throws {
        self.value = try ConditionOperator(from: decoder)
    }
}
