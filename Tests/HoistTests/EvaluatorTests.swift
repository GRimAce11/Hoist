import Testing
@testable import Hoist

@Suite("Evaluator")
struct EvaluatorTests {

    // MARK: - Defaults & fallthrough

    @Test func emptyRulesReturnsDefault() {
        let flag = Flag(key: "x", type: .bool, defaultValue: .bool(false), rules: [])
        let result = Evaluator.evaluate(flag, context: .anonymous)
        #expect(result == .bool(false))
    }

    @Test func noRulesMatchReturnsDefault() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [
                .condition(
                    conditions: [Condition(attribute: "country", operator: .eq(.string("US")))],
                    value: .bool(true)
                )
            ]
        )
        let context = UserContext(attributes: ["country": .string("DE")])
        #expect(Evaluator.evaluate(flag, context: context) == .bool(false))
    }

    // MARK: - Condition rule

    @Test func conditionRuleMatchesEquality() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [
                .condition(
                    conditions: [Condition(attribute: "country", operator: .eq(.string("US")))],
                    value: .bool(true)
                )
            ]
        )
        let context = UserContext(attributes: ["country": .string("US")])
        #expect(Evaluator.evaluate(flag, context: context) == .bool(true))
    }

    @Test func conditionRuleAllConditionsMustMatch() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [
                .condition(
                    conditions: [
                        Condition(attribute: "country", operator: .eq(.string("US"))),
                        Condition(attribute: "plan", operator: .eq(.string("pro"))),
                    ],
                    value: .bool(true)
                )
            ]
        )

        let onlyUS = UserContext(attributes: ["country": .string("US")])
        #expect(Evaluator.evaluate(flag, context: onlyUS) == .bool(false))

        let both = UserContext(attributes: ["country": .string("US"), "plan": .string("pro")])
        #expect(Evaluator.evaluate(flag, context: both) == .bool(true))
    }

    @Test func firstMatchingRuleWins() {
        let flag = Flag(
            key: "x", type: .string, defaultValue: .string("z"),
            rules: [
                .condition(
                    conditions: [Condition(attribute: "country", operator: .eq(.string("US")))],
                    value: .string("a")
                ),
                .condition(
                    conditions: [Condition(attribute: "plan", operator: .eq(.string("pro")))],
                    value: .string("b")
                ),
            ]
        )
        let context = UserContext(attributes: ["country": .string("US"), "plan": .string("pro")])
        #expect(Evaluator.evaluate(flag, context: context) == .string("a"))
    }

    // MARK: - Operators

    @Test func operatorIn() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [
                .condition(
                    conditions: [Condition(
                        attribute: "country",
                        operator: .in([.string("US"), .string("CA")])
                    )],
                    value: .bool(true)
                )
            ]
        )
        #expect(
            Evaluator.evaluate(flag, context: UserContext(attributes: ["country": .string("CA")]))
            == .bool(true)
        )
        #expect(
            Evaluator.evaluate(flag, context: UserContext(attributes: ["country": .string("DE")]))
            == .bool(false)
        )
    }

    @Test func operatorGteWithNumbers() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [
                .condition(
                    conditions: [Condition(attribute: "age", operator: .gte(.int(18)))],
                    value: .bool(true)
                )
            ]
        )
        #expect(Evaluator.evaluate(flag, context: UserContext(attributes: ["age": .int(17)])) == .bool(false))
        #expect(Evaluator.evaluate(flag, context: UserContext(attributes: ["age": .int(18)])) == .bool(true))
        #expect(Evaluator.evaluate(flag, context: UserContext(attributes: ["age": .int(99)])) == .bool(true))
    }

    @Test func operatorEndsWith() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [
                .condition(
                    conditions: [Condition(attribute: "email", operator: .endsWith("@company.com"))],
                    value: .bool(true)
                )
            ]
        )
        #expect(
            Evaluator.evaluate(flag, context: UserContext(attributes: ["email": .string("a@company.com")]))
            == .bool(true)
        )
        #expect(
            Evaluator.evaluate(flag, context: UserContext(attributes: ["email": .string("a@gmail.com")]))
            == .bool(false)
        )
    }

    @Test func operatorTypeMismatchDoesNotMatch() {
        // Comparing string against int should not match (gt is incomparable here).
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [
                .condition(
                    conditions: [Condition(attribute: "age", operator: .gt(.int(10)))],
                    value: .bool(true)
                )
            ]
        )
        let context = UserContext(attributes: ["age": .string("hello")])
        #expect(Evaluator.evaluate(flag, context: context) == .bool(false))
    }

    // MARK: - Rollout rule

    @Test func rolloutSkippedWithoutUserID() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [.rollout(percentage: 100, value: .bool(true))]
        )
        // No userID → rollout cannot bucket → fall through to default.
        #expect(Evaluator.evaluate(flag, context: .anonymous) == .bool(false))
    }

    @Test func rolloutOneHundredAlwaysMatches() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [.rollout(percentage: 100, value: .bool(true))]
        )
        let context = UserContext(userID: "anyone")
        #expect(Evaluator.evaluate(flag, context: context) == .bool(true))
    }

    @Test func rolloutZeroNeverMatches() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [.rollout(percentage: 0, value: .bool(true))]
        )
        let context = UserContext(userID: "anyone")
        #expect(Evaluator.evaluate(flag, context: context) == .bool(false))
    }

    @Test func rolloutIsDeterministicForSameUser() {
        let flag = Flag(
            key: "x", type: .bool, defaultValue: .bool(false),
            rules: [.rollout(percentage: 50, value: .bool(true))]
        )
        let context = UserContext(userID: "user_42")
        let first = Evaluator.evaluate(flag, context: context)
        for _ in 0..<100 {
            #expect(Evaluator.evaluate(flag, context: context) == first)
        }
    }

    @Test func rolloutDistributionIsRoughlyCorrect() {
        // With 10,000 random user IDs and a 25% rollout, we expect ~2,500 hits.
        // Allow ±300 tolerance (very generous; SHA-256 over short strings is well-distributed).
        let flag = Flag(
            key: "marquee", type: .bool, defaultValue: .bool(false),
            rules: [.rollout(percentage: 25, value: .bool(true))]
        )
        var hits = 0
        for i in 0..<10_000 {
            let context = UserContext(userID: "user_\(i)")
            if Evaluator.evaluate(flag, context: context) == .bool(true) { hits += 1 }
        }
        #expect((2200...2800).contains(hits), "rollout count was \(hits), expected ~2500")
    }

    // MARK: - Split rule

    @Test func splitDeterministicForSameUser() {
        let flag = Flag(
            key: "layout", type: .string, defaultValue: .string("grid"),
            rules: [.split(variants: [
                SplitVariant(value: "a", weight: 1),
                SplitVariant(value: "b", weight: 1),
                SplitVariant(value: "c", weight: 1),
            ])]
        )
        let context = UserContext(userID: "user_99")
        let first = Evaluator.evaluate(flag, context: context)
        for _ in 0..<50 {
            #expect(Evaluator.evaluate(flag, context: context) == first)
        }
    }

    @Test func splitWeightsAreApproximatelyHonored() {
        // 80/10/10 split. Across 10k users we expect ~8000 / ~1000 / ~1000.
        let flag = Flag(
            key: "experiment", type: .string, defaultValue: .string("a"),
            rules: [.split(variants: [
                SplitVariant(value: "a", weight: 80),
                SplitVariant(value: "b", weight: 10),
                SplitVariant(value: "c", weight: 10),
            ])]
        )
        var counts: [String: Int] = ["a": 0, "b": 0, "c": 0]
        for i in 0..<10_000 {
            let context = UserContext(userID: "u\(i)")
            if case .string(let v) = Evaluator.evaluate(flag, context: context) {
                counts[v, default: 0] += 1
            }
        }
        #expect((7600...8400).contains(counts["a"]!), "a count was \(counts["a"]!)")
        #expect((800...1200).contains(counts["b"]!),  "b count was \(counts["b"]!)")
        #expect((800...1200).contains(counts["c"]!),  "c count was \(counts["c"]!)")
    }

    @Test func splitSkippedWithoutUserID() {
        let flag = Flag(
            key: "layout", type: .string, defaultValue: .string("grid"),
            rules: [.split(variants: [
                SplitVariant(value: "a", weight: 1),
                SplitVariant(value: "b", weight: 1),
            ])]
        )
        #expect(Evaluator.evaluate(flag, context: .anonymous) == .string("grid"))
    }
}
