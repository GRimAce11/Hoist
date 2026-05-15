import Foundation

/// Pure-function evaluator. Given a flag and a user context, returns the
/// resolved value by walking the flag's rules top-to-bottom.
///
/// The evaluator has no side effects and no I/O — it is fully deterministic
/// for a given `(flag, context)` pair.
enum Evaluator {
    /// Convenience: returns just the value (default behavior).
    static func evaluate(_ flag: Flag, context: UserContext) -> AttributeValue {
        evaluateDetailed(flag, context: context).value
    }

    /// Result of evaluating a flag, including which rule matched (if any).
    /// `matchedRuleIndex == nil` means no rule applied and `flag.defaultValue`
    /// was served.
    struct Outcome {
        let value: AttributeValue
        let matchedRuleIndex: Int?
    }

    /// Walks rules top-to-bottom and reports which rule index matched, so
    /// callers can build A/B-test exposure events with variant attribution.
    static func evaluateDetailed(_ flag: Flag, context: UserContext) -> Outcome {
        for (index, rule) in flag.rules.enumerated() {
            if let value = apply(rule: rule, flag: flag, context: context) {
                return Outcome(value: value, matchedRuleIndex: index)
            }
        }
        return Outcome(value: flag.defaultValue, matchedRuleIndex: nil)
    }

    // MARK: - Per-rule application

    private static func apply(rule: Rule, flag: Flag, context: UserContext) -> AttributeValue? {
        switch rule {
        case .condition(let conditions, let value):
            return matchAll(conditions, in: context) ? value : nil

        case .rollout(let conditions, let percentage, let value):
            guard matchAll(conditions, in: context) else { return nil }
            guard let userID = context.userID else { return nil }
            return Bucketer.percentile(flagKey: flag.key, userID: userID) < percentage
                ? value
                : nil

        case .split(let conditions, let variants):
            guard matchAll(conditions, in: context) else { return nil }
            guard let userID = context.userID else { return nil }
            let total = variants.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return nil }
            var bucket = Bucketer.bucket(flagKey: flag.key, userID: userID, total: total)
            for variant in variants {
                if bucket < variant.weight {
                    return .string(variant.value)
                }
                bucket -= variant.weight
            }
            // Should be unreachable, but fail safely.
            return variants.last.map { .string($0.value) }
        }
    }

    // MARK: - Conditions

    private static func matchAll(_ conditions: [Condition], in context: UserContext) -> Bool {
        for condition in conditions {
            guard let attribute = context.attributes[condition.attribute] else { return false }
            if !match(operator: condition.operator, attribute: attribute) {
                return false
            }
        }
        return true
    }

    private static func match(operator op: ConditionOperator, attribute: AttributeValue) -> Bool {
        switch op {
        case .eq(let value):
            return attribute == value
        case .neq(let value):
            return attribute != value
        case .in(let values):
            return values.contains(attribute)
        case .notIn(let values):
            return !values.contains(attribute)
        case .gt(let value):
            return Self.compare(attribute, value) == .orderedDescending
        case .gte(let value):
            let result = Self.compare(attribute, value)
            return result == .orderedDescending || result == .orderedSame
        case .lt(let value):
            return Self.compare(attribute, value) == .orderedAscending
        case .lte(let value):
            let result = Self.compare(attribute, value)
            return result == .orderedAscending || result == .orderedSame
        case .contains(let needle):
            return attribute.asString?.contains(needle) ?? false
        case .startsWith(let prefix):
            return attribute.asString?.hasPrefix(prefix) ?? false
        case .endsWith(let suffix):
            return attribute.asString?.hasSuffix(suffix) ?? false
        }
    }

    /// Compares two attribute values when an order is meaningful.
    /// Returns `nil` when the values are not comparable (e.g. mixing string and number).
    private static func compare(_ lhs: AttributeValue, _ rhs: AttributeValue) -> ComparisonResult? {
        switch (lhs, rhs) {
        case (.int(let l), .int(let r)):
            return order(l, r)
        case (.double(let l), .double(let r)):
            return order(l, r)
        case (.int(let l), .double(let r)):
            return order(Double(l), r)
        case (.double(let l), .int(let r)):
            return order(l, Double(r))
        case (.string(let l), .string(let r)):
            return l.compare(r)
        case (.bool(let l), .bool(let r)):
            return order(l ? 1 : 0, r ? 1 : 0)
        default:
            return nil
        }
    }

    private static func order<T: Comparable>(_ l: T, _ r: T) -> ComparisonResult {
        l < r ? .orderedAscending : l > r ? .orderedDescending : .orderedSame
    }
}
