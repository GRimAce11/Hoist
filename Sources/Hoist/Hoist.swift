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
    private static let evaluationHookLock = OSAllocatedUnfairLock<(@Sendable (EvaluationEvent) -> Void)?>(initialState: nil)

    // MARK: - Analytics exposure hook

    /// A closure invoked once per public read (`bool` / `int` / `double` /
    /// `string`) with the value Hoist actually served and where it came from.
    /// Wire this up to your analytics SDK to attribute conversion events to
    /// A/B-test variants.
    ///
    /// ```swift
    /// Hoist.onEvaluate = { event in
    ///     analytics.track("flag_exposure", properties: [
    ///         "flag":   event.flagKey,
    ///         "value":  String(describing: event.value),
    ///         "source": String(describing: event.source),
    ///     ])
    /// }
    /// ```
    ///
    /// Set once at app launch — typically before `configure(...)`. The hook
    /// is invoked synchronously on the thread that performed the read, so
    /// heavy work (network I/O, file writes) should be dispatched out.
    public static var onEvaluate: (@Sendable (EvaluationEvent) -> Void)? {
        get { evaluationHookLock.withLock { $0 } }
        set { evaluationHookLock.withLock { $0 = newValue } }
    }

    private static func fire(_ event: EvaluationEvent) {
        // Snapshot the hook under its own lock, then call it OUTSIDE the lock.
        // Storage is a separate lock; reading either lock from inside the
        // user's hook is safe.
        let hook = evaluationHookLock.withLock { $0 }
        hook?(event)
    }

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
    /// If the source contains a `.url(_, pollInterval: X)` case (directly or
    /// nested inside `.layered(...)`), Hoist starts a background task that
    /// re-loads the source every `X` seconds, sending the cached `ETag` via
    /// `If-None-Match` to avoid redundant downloads.
    ///
    /// Call this once at app launch. May be called again to reload — listeners
    /// observing `HoistObservable.shared` will be notified. Concurrent calls
    /// are not supported.
    public static func configure(source: FlagSource, context: UserContext) async throws {
        cancelPolling()
        let document = try await source.load()
        let registry = FlagRegistry(document: document)
        let savedOverrides = overrideStore.load()
        storage.withLock { state in
            state.registry = registry
            state.context = context
            state.overrides = savedOverrides
        }
        await HoistObservable.shared.tick()
        if let interval = source.shortestPollInterval, interval > 0 {
            startPolling(source: source, interval: interval)
        }
    }

    /// Updates only the user context (e.g. on login/logout) without reloading flags.
    public static func update(context: UserContext) async {
        storage.withLock { $0.context = context }
        await HoistObservable.shared.tick()
    }

    /// Resets all state, including persisted overrides. Mostly useful in tests.
    public static func reset() async {
        storage.withLock { state in
            state.pollingTask?.cancel()
            state = .empty
        }
        overrideStore.clearAll()
        await HoistObservable.shared.tick()
    }

    // MARK: - Remote cache (internal — used by FlagSource.loadRemote)

    static func cachedRemoteDocument(for url: URL) -> CachedRemoteDocument? {
        storage.withLock { $0.remoteCache[url] }
    }

    static func setCachedRemoteDocument(_ doc: CachedRemoteDocument, for url: URL) {
        storage.withLock { $0.remoteCache[url] = doc }
    }

    // MARK: - Polling (internal)

    private static func cancelPolling() {
        storage.withLock { state in
            state.pollingTask?.cancel()
            state.pollingTask = nil
        }
    }

    private static func startPolling(source: FlagSource, interval: TimeInterval) {
        let task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                if Task.isCancelled { return }
                do {
                    let document = try await source.load()
                    if Task.isCancelled { return }
                    let registry = FlagRegistry(document: document)
                    storage.withLock { $0.registry = registry }
                    await HoistObservable.shared.tick()
                } catch {
                    // Refresh failure is non-fatal; try again on the next tick.
                }
            }
        }
        storage.withLock { $0.pollingTask = task }
    }

    // MARK: - Reads
    //
    // All read methods are synchronous and thread-safe. They return the
    // resolved value (override → rule → flag default) when the flag exists,
    // and the caller-supplied `defaultValue` when the flag is missing, the
    // resolved value cannot be coerced to the requested type, or `configure`
    // has not yet completed. Each call also fires `onEvaluate` (if set) with
    // the actually-served value and where it came from.

    /// Returns the boolean value of `key`, or `defaultValue` if the flag is
    /// missing or its resolved value isn't a boolean.
    public static func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        let resolution = resolve(key)
        if let asBool = resolution.value?.asBool {
            emit(key: key, value: .bool(asBool), source: resolution.source)
            return asBool
        }
        emit(key: key, value: .bool(defaultValue), source: .fallback)
        return defaultValue
    }

    /// Returns the integer value of `key`, or `defaultValue` if the flag is
    /// missing or its resolved value isn't an integer.
    public static func int(_ key: String, default defaultValue: Int = 0) -> Int {
        let resolution = resolve(key)
        if let asInt = resolution.value?.asInt {
            emit(key: key, value: .int(asInt), source: resolution.source)
            return asInt
        }
        emit(key: key, value: .int(defaultValue), source: .fallback)
        return defaultValue
    }

    /// Returns the floating-point value of `key`, or `defaultValue` if the flag
    /// is missing or its resolved value isn't numeric.
    public static func double(_ key: String, default defaultValue: Double = 0) -> Double {
        let resolution = resolve(key)
        if let asDouble = resolution.value?.asDouble {
            emit(key: key, value: .double(asDouble), source: resolution.source)
            return asDouble
        }
        emit(key: key, value: .double(defaultValue), source: .fallback)
        return defaultValue
    }

    /// Returns the string value of `key`, or `defaultValue` if the flag is
    /// missing or its resolved value isn't a string.
    public static func string(_ key: String, default defaultValue: String = "") -> String {
        let resolution = resolve(key)
        if let asString = resolution.value?.asString {
            emit(key: key, value: .string(asString), source: resolution.source)
            return asString
        }
        emit(key: key, value: .string(defaultValue), source: .fallback)
        return defaultValue
    }

    private static func emit(key: String, value: AttributeValue, source: EvaluationSource) {
        let userID = storage.withLock { $0.context.userID }
        fire(EvaluationEvent(flagKey: key, value: value, source: source, userID: userID))
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

    struct Resolution {
        let value: AttributeValue?
        let source: EvaluationSource
    }

    static func resolve(_ key: String) -> Resolution {
        storage.withLock { state -> Resolution in
            if let override = state.overrides[key] {
                return Resolution(value: override, source: .override)
            }
            guard let flag = state.registry.flag(for: key) else {
                return Resolution(value: nil, source: .fallback)
            }
            let outcome = Evaluator.evaluateDetailed(flag, context: state.context)
            let source: EvaluationSource = outcome.matchedRuleIndex
                .map(EvaluationSource.rule(index:))
                ?? .defaultValue
            return Resolution(value: outcome.value, source: source)
        }
    }
}

/// A remote flag document held alongside the `ETag` it was served with, so
/// the next refresh can ask the server "still the same?" via `If-None-Match`
/// and short-circuit on a `304 Not Modified` response.
struct CachedRemoteDocument: Sendable {
    let etag: String
    let document: FlagDocument
}

/// Thread-protected mutable state held by `Hoist`.
struct Storage: Sendable {
    var registry: FlagRegistry
    var context: UserContext
    var overrides: [String: AttributeValue]
    var pollingTask: Task<Void, Never>?
    var remoteCache: [URL: CachedRemoteDocument]

    static let empty = Storage(
        registry: .empty,
        context: .anonymous,
        overrides: [:],
        pollingTask: nil,
        remoteCache: [:]
    )
}
