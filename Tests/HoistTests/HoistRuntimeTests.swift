import Testing
import Foundation
@testable import Hoist

/// Tests that exercise Hoist's global runtime state (configure / overrides /
/// reset / context updates). They share a single global `Hoist` enum and a
/// shared `UserDefaults` suite, so they MUST run serially.
///
/// The `.serialized` trait on this outer suite forces all nested tests —
/// including those across nested suites — to run one at a time.
@Suite("Hoist runtime", .serialized)
struct HoistRuntime {

    /// Resets all state, then loads the bundled sample-flags.json with the given context.
    /// Used as the setup hook by every nested test.
    fileprivate static func freshConfigure(context: UserContext) async throws {
        await Hoist.reset()
        try await Hoist.configure(
            source: .bundled(filename: "sample-flags.json", bundle: .module),
            context: context
        )
    }

    // MARK: - Public API

    @Suite("Public API")
    struct PublicAPI {

        @Test func boolFlagHonoursContext() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "alice",
                attributes: ["country": .string("US")]
            ))
            #expect(Hoist.bool("bool_country_us") == true)
            #expect(Hoist.bool("bool_off") == false)
        }

        @Test func boolFlagFallsThroughForOtherCountry() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "alice",
                attributes: ["country": .string("DE")]
            ))
            #expect(Hoist.bool("bool_country_us") == false)
        }

        @Test func intFlagReturnsRuleValueForProUser() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "alice",
                attributes: ["plan": .string("pro")]
            ))
            #expect(Hoist.int("int_pro_user") == 100)
        }

        @Test func intFlagReturnsDefaultForFreeUser() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "alice",
                attributes: ["plan": .string("free")]
            ))
            #expect(Hoist.int("int_pro_user") == 10)
        }

        @Test func unknownFlagReturnsCallerDefault() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            #expect(Hoist.bool("does_not_exist", default: true) == true)
            #expect(Hoist.int("does_not_exist", default: 42) == 42)
            #expect(Hoist.string("does_not_exist", default: "fallback") == "fallback")
        }

        @Test func updateContextChangesEvaluation() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
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
            try await HoistRuntime.freshConfigure(
                context: UserContext(attributes: ["country": .string("US")])
            )
            #expect(Hoist.bool("bool_country_us") == true)

            await Hoist.reset()

            #expect(Hoist.bool("bool_country_us") == false)
            #expect(Hoist.allFlagKeys.isEmpty)
        }

        @Test func allFlagKeysAreSorted() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            let keys = Hoist.allFlagKeys
            #expect(keys == keys.sorted())
            #expect(keys.contains("bool_country_us"))
        }

        @Test func flagDefinitionExposesType() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            #expect(Hoist.flag(for: "bool_country_us")?.type == .bool)
            #expect(Hoist.flag(for: "int_pro_user")?.type == .int)
            #expect(Hoist.flag(for: "string_layout_split")?.type == .string)
            #expect(Hoist.flag(for: "missing") == nil)
        }
    }

    // MARK: - Overrides

    @Suite("Overrides")
    struct Overrides {

        @Test func overrideTakesPrecedenceOverRule() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "alice",
                attributes: ["country": .string("DE")]
            ))
            #expect(Hoist.bool("bool_country_us") == false)

            Hoist.override("bool_country_us", with: .bool(true))

            #expect(Hoist.bool("bool_country_us") == true)
            #expect(Hoist.isOverridden("bool_country_us") == true)
        }

        @Test func overrideTakesPrecedenceOverDefault() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            #expect(Hoist.int("int_pro_user") == 10)

            Hoist.override("int_pro_user", with: .int(999))

            #expect(Hoist.int("int_pro_user") == 999)
        }

        @Test func clearOverrideRevertsToRuleEvaluation() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "bob",
                attributes: ["country": .string("US")]
            ))
            Hoist.override("bool_country_us", with: .bool(false))
            #expect(Hoist.bool("bool_country_us") == false)

            Hoist.clearOverride("bool_country_us")

            #expect(Hoist.bool("bool_country_us") == true)
            #expect(Hoist.isOverridden("bool_country_us") == false)
        }

        @Test func clearAllOverridesRemovesEverything() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("bool_country_us", with: .bool(true))
            Hoist.override("int_pro_user", with: .int(50))
            #expect(Hoist.overrides.count == 2)

            Hoist.clearAllOverrides()

            #expect(Hoist.overrides.isEmpty)
            #expect(Hoist.isOverridden("bool_country_us") == false)
            #expect(Hoist.isOverridden("int_pro_user") == false)
        }

        @Test func overridesAreIsolatedAcrossKeys() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("bool_country_us", with: .bool(true))

            #expect(Hoist.bool("bool_country_us") == true)
            #expect(Hoist.bool("bool_off") == false)
        }

        @Test func overrideOfUnknownFlagStillApplies() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("never_defined", with: .bool(true))

            #expect(Hoist.bool("never_defined", default: false) == true)
        }

        @Test func overridesPersistAcrossConfigureCalls() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("bool_country_us", with: .bool(true))

            try await Hoist.configure(
                source: .bundled(filename: "sample-flags.json", bundle: .module),
                context: UserContext(userID: "carol", attributes: ["country": .string("DE")])
            )

            #expect(Hoist.bool("bool_country_us") == true)
            #expect(Hoist.isOverridden("bool_country_us") == true)
        }

        @Test func resetClearsOverrides() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("bool_country_us", with: .bool(true))
            await Hoist.reset()

            #expect(Hoist.overrides.isEmpty)
        }

        @Test func typeMismatchedOverrideFallsThrough() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("bool_country_us", with: .string("nonsense"))

            #expect(Hoist.bool("bool_country_us", default: true) == true)
            #expect(Hoist.bool("bool_country_us", default: false) == false)
        }

        @Test func overridesSnapshotIsImmutable() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("bool_country_us", with: .bool(true))
            let snapshot = Hoist.overrides

            Hoist.clearAllOverrides()

            #expect(snapshot["bool_country_us"] == .bool(true))
            #expect(Hoist.overrides.isEmpty)
        }
    }
}
