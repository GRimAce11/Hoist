import Testing
import Foundation
import os
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

    // MARK: - Polling lifecycle

    @Suite("Polling")
    struct Polling {

        @Test func configureWithoutPollIntervalDoesNotSpawnTask() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            let hasTask = Hoist.storage.withLock { $0.pollingTask != nil }
            #expect(hasTask == false)
        }

        @Test func configureWithPollIntervalSpawnsTask() async throws {
            let url = try #require(Bundle.module.url(forResource: "sample-flags", withExtension: "json"))
            await Hoist.reset()
            try await Hoist.configure(
                source: .url(url, pollInterval: 60),
                context: .anonymous
            )
            let task = Hoist.storage.withLock { $0.pollingTask }
            #expect(task != nil)
            #expect(task?.isCancelled == false)
            await Hoist.reset()
        }

        @Test func resetCancelsPollingTask() async throws {
            let url = try #require(Bundle.module.url(forResource: "sample-flags", withExtension: "json"))
            await Hoist.reset()
            try await Hoist.configure(
                source: .url(url, pollInterval: 60),
                context: .anonymous
            )
            let task = Hoist.storage.withLock { $0.pollingTask }
            #expect(task != nil)

            await Hoist.reset()

            #expect(task?.isCancelled == true)
            let cleared = Hoist.storage.withLock { $0.pollingTask == nil }
            #expect(cleared == true)
        }

        @Test func secondConfigureCancelsPriorPollingTask() async throws {
            let url = try #require(Bundle.module.url(forResource: "sample-flags", withExtension: "json"))
            await Hoist.reset()
            try await Hoist.configure(
                source: .url(url, pollInterval: 60),
                context: .anonymous
            )
            let firstTask = Hoist.storage.withLock { $0.pollingTask }

            try await Hoist.configure(
                source: .url(url, pollInterval: 30),
                context: .anonymous
            )
            let secondTask = Hoist.storage.withLock { $0.pollingTask }

            #expect(firstTask?.isCancelled == true)
            #expect(secondTask != nil)
            #expect(secondTask?.isCancelled == false)
            await Hoist.reset()
        }

        @Test func layeredWithPollingSpawnsTask() async throws {
            let url = try #require(Bundle.module.url(forResource: "sample-flags", withExtension: "json"))
            await Hoist.reset()
            try await Hoist.configure(
                source: .layered([
                    .bundled(filename: "sample-flags.json", bundle: .module),
                    .url(url, pollInterval: 30),
                ]),
                context: .anonymous
            )
            let task = Hoist.storage.withLock { $0.pollingTask }
            #expect(task != nil)
            #expect(task?.isCancelled == false)
            await Hoist.reset()
        }
    }

    // MARK: - onEvaluate hook

    /// Thread-safe collector used by `onEvaluate` tests. Each test installs a
    /// fresh instance and clears `Hoist.onEvaluate` on exit.
    final class EventCollector: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock<[EvaluationEvent]>(initialState: [])
        func record(_ event: EvaluationEvent) { lock.withLock { $0.append(event) } }
        var events: [EvaluationEvent] { lock.withLock { $0 } }
        var last: EvaluationEvent? { lock.withLock { $0.last } }
    }

    @Suite("Evaluation hook")
    struct EvaluationHook {

        @Test func hookFiresForBoolRead() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "alice", attributes: ["country": .string("US")]
            ))
            let collector = EventCollector()
            Hoist.onEvaluate = { collector.record($0) }
            defer { Hoist.onEvaluate = nil }

            _ = Hoist.bool("bool_country_us")

            #expect(collector.events.count == 1)
            #expect(collector.last?.flagKey == "bool_country_us")
            #expect(collector.last?.value == .bool(true))
            #expect(collector.last?.userID == "alice")
        }

        @Test func reportsRuleIndexForMatchedRule() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "alice", attributes: ["country": .string("US")]
            ))
            let collector = EventCollector()
            Hoist.onEvaluate = { collector.record($0) }
            defer { Hoist.onEvaluate = nil }

            _ = Hoist.bool("bool_country_us")

            #expect(collector.last?.source == .rule(index: 0))
        }

        @Test func reportsDefaultValueWhenNoRuleMatches() async throws {
            try await HoistRuntime.freshConfigure(context: UserContext(
                userID: "alice", attributes: ["country": .string("DE")]
            ))
            let collector = EventCollector()
            Hoist.onEvaluate = { collector.record($0) }
            defer { Hoist.onEvaluate = nil }

            _ = Hoist.bool("bool_country_us")

            #expect(collector.last?.source == .defaultValue)
            #expect(collector.last?.value == .bool(false))
        }

        @Test func reportsOverrideSource() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("bool_country_us", with: .bool(true))
            let collector = EventCollector()
            Hoist.onEvaluate = { collector.record($0) }
            defer {
                Hoist.onEvaluate = nil
                Hoist.clearAllOverrides()
            }

            _ = Hoist.bool("bool_country_us")

            #expect(collector.last?.source == .override)
            #expect(collector.last?.value == .bool(true))
        }

        @Test func reportsFallbackForMissingFlag() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            let collector = EventCollector()
            Hoist.onEvaluate = { collector.record($0) }
            defer { Hoist.onEvaluate = nil }

            _ = Hoist.bool("does_not_exist", default: true)

            #expect(collector.last?.source == .fallback)
            #expect(collector.last?.value == .bool(true))
        }

        @Test func reportsFallbackForTypeMismatchedOverride() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.override("bool_country_us", with: .string("nonsense"))
            let collector = EventCollector()
            Hoist.onEvaluate = { collector.record($0) }
            defer {
                Hoist.onEvaluate = nil
                Hoist.clearAllOverrides()
            }

            _ = Hoist.bool("bool_country_us", default: true)

            #expect(collector.last?.source == .fallback)
            #expect(collector.last?.value == .bool(true))
        }

        @Test func firesForAllReadTypes() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            let collector = EventCollector()
            Hoist.onEvaluate = { collector.record($0) }
            defer { Hoist.onEvaluate = nil }

            _ = Hoist.bool("bool_off")
            _ = Hoist.int("int_pro_user")
            _ = Hoist.double("missing_double", default: 1.5)
            _ = Hoist.string("string_layout_split")

            #expect(collector.events.count == 4)
            #expect(collector.events.map(\.flagKey) == [
                "bool_off", "int_pro_user", "missing_double", "string_layout_split"
            ])
        }

        @Test func nilHookIsSafe() async throws {
            try await HoistRuntime.freshConfigure(context: .anonymous)
            Hoist.onEvaluate = nil
            // Should not crash, just return the value.
            _ = Hoist.bool("bool_off")
        }
    }
}
