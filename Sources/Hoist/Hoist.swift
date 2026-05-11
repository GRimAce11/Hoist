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
    private static let exposureDedupLock = OSAllocatedUnfairLock<ExposureDedup>(initialState: .perSession)
    private static let urlSessionLock = OSAllocatedUnfairLock<URLSession>(initialState: .shared)

    // MARK: - URLSession (internal seam for tests; defaults to `.shared`)

    /// The `URLSession` used by `FlagSource.url(...)` fetches. Defaults to
    /// `URLSession.shared`. Internal so test code can swap in a custom
    /// session configured with a stub `URLProtocol`. Production code should
    /// not need to touch this.
    static var urlSession: URLSession {
        get { urlSessionLock.withLock { $0 } }
        set { urlSessionLock.withLock { $0 = newValue } }
    }

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

    /// Controls whether `onEvaluate` is invoked on every public read or
    /// collapsed to one event per unique `(flagKey, userID, value, source)`
    /// tuple until the next `configure(...)` or `reset()`. Defaults to
    /// `.perSession` — see `ExposureDedup` for the rationale.
    public static var exposureDedup: ExposureDedup {
        get { exposureDedupLock.withLock { $0 } }
        set { exposureDedupLock.withLock { $0 = newValue } }
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
            // A new configure starts a fresh exposure session, so the next
            // read of every flag fires the hook at least once.
            state.exposedEvents.removeAll()
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
            // `consecutiveFailures` powers an exponential backoff (capped at
            // 16× the base interval) so a flapping endpoint doesn't get
            // hammered every `interval` seconds during an outage. Resets to
            // zero on the first successful refresh.
            var consecutiveFailures = 0
            // ±10% randomized jitter keeps a million apps from aligning to
            // exact minute boundaries and thundering-herding the origin.
            while !Task.isCancelled {
                let backoff = min(pow(2.0, Double(consecutiveFailures)), 16.0)
                let jitter = Double.random(in: 0.9...1.1)
                let delay = interval * backoff * jitter
                do {
                    try await Task.sleep(for: .seconds(delay))
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
                    consecutiveFailures = 0
                } catch {
                    consecutiveFailures = min(consecutiveFailures + 1, 4)
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
        // Cheap nil-hook check first — most apps never set `onEvaluate`, so
        // we avoid touching the storage lock entirely on the hot path.
        guard let hook = evaluationHookLock.withLock({ $0 }) else { return }
        let policy = exposureDedupLock.withLock { $0 }
        let userID = storage.withLock { $0.context.userID }
        if policy == .perSession {
            let dedupKey = DedupKey(flagKey: key, userID: userID, value: value, source: source)
            let shouldFire = storage.withLock { state in
                state.exposedEvents.insert(dedupKey).inserted
            }
            guard shouldFire else { return }
        }
        hook(EvaluationEvent(flagKey: key, value: value, source: source, userID: userID))
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

/// Identifies a unique flag exposure for `ExposureDedup.perSession`. Two
/// reads produce the same key when the flag, user, served value, and source
/// all match, so the hook only fires when one of them changes.
struct DedupKey: Hashable, Sendable {
    let flagKey: String
    let userID: String?
    let value: AttributeValue
    let source: EvaluationSource
}

/// Thread-protected mutable state held by `Hoist`.
struct Storage: Sendable {
    var registry: FlagRegistry
    var context: UserContext
    var overrides: [String: AttributeValue]
    var pollingTask: Task<Void, Never>?
    var remoteCache: [URL: CachedRemoteDocument]
    var exposedEvents: Set<DedupKey>

    static let empty = Storage(
        registry: .empty,
        context: .anonymous,
        overrides: [:],
        pollingTask: nil,
        remoteCache: [:],
        exposedEvents: []
    )
}
