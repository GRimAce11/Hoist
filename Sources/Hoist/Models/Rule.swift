import Foundation

/// A single rule in a flag's `rules` array. Evaluated top-to-bottom; first match wins.
public enum Rule: Sendable, Equatable {
    /// All conditions must match (AND). Returns `value` on match.
    case condition(conditions: [Condition], value: AttributeValue)

    /// Returns `value` if `hash(flagKey + userID) % 100 < percentage`.
    /// If `conditions` is non-empty, they must all match before the user is bucketed.
    case rollout(conditions: [Condition], percentage: Int, value: AttributeValue)

    /// Deterministically picks one variant by weight. Variant string becomes the value.
    /// Only meaningful for string flags.
    /// If `conditions` is non-empty, they must all match before the user is bucketed.
    case split(conditions: [Condition], variants: [SplitVariant])
}

extension Rule {
    /// Ungated rollout — sugar for `.rollout(conditions: [], ...)`.
    public static func rollout(percentage: Int, value: AttributeValue) -> Rule {
        .rollout(conditions: [], percentage: percentage, value: value)
    }

    /// Ungated split — sugar for `.split(conditions: [], ...)`.
    public static func split(variants: [SplitVariant]) -> Rule {
        .split(conditions: [], variants: variants)
    }
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

        let conditions: [Condition] = container.contains(.if)
            ? try Self.decodeConditions(from: container)
            : []

        // 1. Split rule (optionally gated by `if`).
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
            self = .split(conditions: conditions, variants: variants)
            return
        }

        // 2. Rollout rule (optionally gated by `if`).
        if container.contains(.rollout) {
            let percentage = try container.decode(Int.self, forKey: .rollout)
            guard (0...100).contains(percentage) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .rollout, in: container,
                    debugDescription: "rollout percentage must be in 0...100"
                )
            }
            let value = try container.decode(AttributeValue.self, forKey: .value)
            self = .rollout(conditions: conditions, percentage: percentage, value: value)
            return
        }

        // 3. Plain condition rule — `if` + `value`, no rollout/split.
        if container.contains(.if) {
            let value = try container.decode(AttributeValue.self, forKey: .value)
            self = .condition(conditions: conditions, value: value)
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .if, in: container,
            debugDescription: "Rule must contain one of: 'if', 'rollout', 'split'"
        )
    }

    private static func decodeConditions(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [Condition] {
        let predicates = try container.decode([String: ConditionOperatorBox].self, forKey: .if)
        return predicates
            .map { Condition(attribute: $0.key, operator: $0.value.value) }
            .sorted { $0.attribute < $1.attribute }   // stable order for tests
    }
}

/// Wrapper to invoke `ConditionOperator`'s custom decoder when used as a dictionary value.
private struct ConditionOperatorBox: Decodable {
    let value: ConditionOperator
    init(from decoder: Decoder) throws {
        self.value = try ConditionOperator(from: decoder)
    }
}
