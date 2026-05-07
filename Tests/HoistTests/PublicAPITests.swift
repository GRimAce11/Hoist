import Testing
import Foundation
@testable import Hoist

@Suite("Hoist public API", .serialized)
struct PublicAPITests {

    @Test func boolFlagHonoursContext() async throws {
        try await configureSampleFlags(context: UserContext(
            userID: "alice",
            attributes: ["country": .string("US")]
        ))
        #expect(Hoist.bool("bool_country_us") == true)
        #expect(Hoist.bool("bool_off") == false)
    }

    @Test func boolFlagFallsThroughForOtherCountry() async throws {
        try await configureSampleFlags(context: UserContext(
            userID: "alice",
            attributes: ["country": .string("DE")]
        ))
        #expect(Hoist.bool("bool_country_us") == false)
    }

    @Test func intFlagReturnsRuleValueForProUser() async throws {
        try await configureSampleFlags(context: UserContext(
            userID: "alice",
            attributes: ["plan": .string("pro")]
        ))
        #expect(Hoist.int("int_pro_user") == 100)
    }

    @Test func intFlagReturnsDefaultForFreeUser() async throws {
        try await configureSampleFlags(context: UserContext(
            userID: "alice",
            attributes: ["plan": .string("free")]
        ))
        #expect(Hoist.int("int_pro_user") == 10)
    }

    @Test func unknownFlagReturnsCallerDefault() async throws {
        try await configureSampleFlags(context: .anonymous)
        #expect(Hoist.bool("does_not_exist", default: true) == true)
        #expect(Hoist.int("does_not_exist", default: 42) == 42)
        #expect(Hoist.string("does_not_exist", default: "fallback") == "fallback")
    }

    @Test func updateContextChangesEvaluation() async throws {
        try await configureSampleFlags(context: UserContext(
            userID: "alice",
            attributes: ["country": .string("DE")]
        ))
        #expect(Hoist.bool("bool_country_us") == false)

        await Hoist.update(context: UserContext(
            userID: "alice",
            attributes: ["country": .string("US")]
        ))
        #expect(Hoist.bool("bool_country_us") == true)
    }

    @Test func resetClearsState() async throws {
        try await configureSampleFlags(context: UserContext(attributes: ["country": .string("US")]))
        #expect(Hoist.bool("bool_country_us") == true)
        await Hoist.reset()
        #expect(Hoist.bool("bool_country_us") == false)
        #expect(Hoist.allFlagKeys.isEmpty)
    }

    @Test func allFlagKeysAreSorted() async throws {
        try await configureSampleFlags(context: .anonymous)
        let keys = Hoist.allFlagKeys
        #expect(keys == keys.sorted())
        #expect(keys.contains("bool_country_us"))
    }

    // MARK: - Helpers

    /// Loads the bundled sample-flags.json with the given context.
    private func configureSampleFlags(context: UserContext) async throws {
        try await Hoist.configure(
            source: .bundled(filename: "sample-flags.json", bundle: .module),
            context: context
        )
    }
}
