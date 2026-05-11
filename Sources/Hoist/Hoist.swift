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
    static let storage = OSAllocatedUnfairLock<Storage>(initialState: .empty)
    static let overrideStore = OverrideStore()

    // MARK: - Schema versioning

    /// The schema version that new flag documents should declare. Files that
    /// omit `schemaVersion` are treated as version `1` for backwards
    /// compatibility with pre-0.2.2 documents.
    public static let currentSchemaVersion: Int = 1

    /// All schema versions this build of Hoist can load. Documents that
    /// declare a `schemaVersion` outside this set fail to load with
    /// `FlagSourceError.unsupportedSchemaVersion`.
    public static let supportedSchemaVersions: Set<Int> = [1]

    // MARK: - Configuration

    /// Loads the flag document from `source` and stores `context` for evaluation.
    /// Saved overrides (if any) are restored from disk.
    ///
    /// Call this once at app launch. May be called again to reload — listeners
    /// observing `HoistObservable.shared` will be notified.
    public static func configure(source: FlagSource, context: UserContext) async throws {
        let document = try await source.load()
        let registry = FlagRegistry(document: document)
        let savedOverrides = overrideStore.load()
        storage.withLock { state in
            state.registry = registry
            state.context = context
            state.overrides = savedOverrides
        }
        await HoistObservable.shared.tick()
    }

    /// Updates only the user context (e.g. on login/logout) without reloading flags.
    public static func update(context: UserContext) async {
        storage.withLock { $0.context = context }
        await HoistObservable.shared.tick()
    }

    /// Resets all state, including persisted overrides. Mostly useful in tests.
    public static func reset() async {
        storage.withLock { $0 = .empty }
        overrideStore.clearAll()
        await HoistObservable.shared.tick()
    }

    // MARK: - Reads
    //
    // All read methods are synchronous and thread-safe. They return the
    // resolved value (override → rule → flag default) when the flag exists,
    // and the caller-supplied `defaultValue` when the flag is missing, the
    // resolved value cannot be coerced to the requested type, or `configure`
    // has not yet completed.

    /// Returns the boolean value of `key`, or `defaultValue` if the flag is
    /// missing or its resolved value isn't a boolean.
    public static func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        resolve(key)?.asBool ?? defaultValue
    }

    /// Returns the integer value of `key`, or `defaultValue` if the flag is
    /// missing or its resolved value isn't an integer.
    public static func int(_ key: String, default defaultValue: Int = 0) -> Int {
        resolve(key)?.asInt ?? defaultValue
    }

    /// Returns the floating-point value of `key`, or `defaultValue` if the flag
    /// is missing or its resolved value isn't numeric.
    public static func double(_ key: String, default defaultValue: Double = 0) -> Double {
        resolve(key)?.asDouble ?? defaultValue
    }

    /// Returns the string value of `key`, or `defaultValue` if the flag is
    /// missing or its resolved value isn't a string.
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

    /// Returns the parsed flag definition for `key`, or `nil` if no such flag exists.
    /// Mainly useful for debug UIs that need to know a flag's declared type.
    public static func flag(for key: String) -> Flag? {
        storage.withLock { $0.registry.flag(for: key) }
    }

    // MARK: - Internal

    static func resolve(_ key: String) -> AttributeValue? {
        storage.withLock { state -> AttributeValue? in
            if let override = state.overrides[key] { return override }
            guard let flag = state.registry.flag(for: key) else { return nil }
            return Evaluator.evaluate(flag, context: state.context)
        }
    }
}

/// Thread-protected mutable state held by `Hoist`.
struct Storage: Sendable {
    var registry: FlagRegistry
    var context: UserContext
    var overrides: [String: AttributeValue]

    static let empty = Storage(registry: .empty, context: .anonymous, overrides: [:])
}
