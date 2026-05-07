import Foundation
import os

/// Hoist — a lightweight, type-safe feature-flag library for Swift.
///
/// ## Configure once
///
/// ```swift
/// try await Hoist.configure(
///     source: .bundled(filename: "flags.json"),
///     context: UserContext(userID: user.id, attributes: ["country": .string("US")])
/// )
/// ```
///
/// ## Read flag values
///
/// ```swift
/// if Hoist.bool("new_checkout") { ... }
/// let limit = Hoist.int("max_upload_mb", default: 10)
/// ```
///
/// All read methods are thread-safe and synchronous.
public enum Hoist {
    private static let storage = OSAllocatedUnfairLock<Storage>(initialState: .empty)

    // MARK: - Configuration

    /// Loads the flag document from `source` and stores `context` for evaluation.
    ///
    /// Call this once at app launch. May be called again to reload — listeners
    /// observing `HoistObservable.shared` will be notified.
    public static func configure(source: FlagSource, context: UserContext) async throws {
        let document = try await source.load()
        let registry = FlagRegistry(document: document)
        storage.withLock { state in
            state.registry = registry
            state.context = context
        }
        await HoistObservable.shared.tick()
    }

    /// Updates only the user context (e.g. on login/logout) without reloading flags.
    public static func update(context: UserContext) async {
        storage.withLock { $0.context = context }
        await HoistObservable.shared.tick()
    }

    /// Resets all state. Mostly useful in tests.
    public static func reset() async {
        storage.withLock { $0 = .empty }
        await HoistObservable.shared.tick()
    }

    // MARK: - Reads

    public static func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        resolve(key)?.asBool ?? defaultValue
    }

    public static func int(_ key: String, default defaultValue: Int = 0) -> Int {
        resolve(key)?.asInt ?? defaultValue
    }

    public static func double(_ key: String, default defaultValue: Double = 0) -> Double {
        resolve(key)?.asDouble ?? defaultValue
    }

    public static func string(_ key: String, default defaultValue: String = "") -> String {
        resolve(key)?.asString ?? defaultValue
    }

    // MARK: - Introspection (mainly for tests / debug UIs)

    /// Returns a snapshot of all known flag keys.
    public static var allFlagKeys: [String] {
        storage.withLock { Array($0.registry.flags.keys).sorted() }
    }

    /// Returns the current user context.
    public static var currentContext: UserContext {
        storage.withLock { $0.context }
    }

    // MARK: - Internal

    private static func resolve(_ key: String) -> AttributeValue? {
        storage.withLock { state -> AttributeValue? in
            guard let flag = state.registry.flag(for: key) else { return nil }
            return Evaluator.evaluate(flag, context: state.context)
        }
    }
}

/// Thread-protected mutable state held by `Hoist`.
private struct Storage: Sendable {
    var registry: FlagRegistry
    var context: UserContext

    static let empty = Storage(registry: .empty, context: .anonymous)
}
