import Foundation

extension Hoist {

    // MARK: - Overrides
    //
    // Overrides bypass rule evaluation entirely. They're persisted to a
    // dedicated `UserDefaults` suite (`com.hoist.overrides`) so they survive
    // app launches. Resolution order is: override → rule → flag default.
    //
    // The override API is unconditional — it works in DEBUG and release. If
    // you don't want users seeing your debug overlay in production, gate the
    // *UI* with `#if DEBUG`, not the API.

    /// Forces `key` to evaluate to `value`, ignoring any rules. Persisted.
    public static func override(_ key: String, with value: AttributeValue) {
        let snapshot = storage.withLock { state -> [String: AttributeValue] in
            state.overrides[key] = value
            return state.overrides
        }
        overrideStore.save(snapshot)
        Task { await HoistObservable.shared.tick() }
    }

    /// Removes an override for `key`. Subsequent reads fall back to rule evaluation.
    public static func clearOverride(_ key: String) {
        let snapshot = storage.withLock { state -> [String: AttributeValue] in
            state.overrides.removeValue(forKey: key)
            return state.overrides
        }
        overrideStore.save(snapshot)
        Task { await HoistObservable.shared.tick() }
    }

    /// Removes every override.
    public static func clearAllOverrides() {
        storage.withLock { $0.overrides.removeAll() }
        overrideStore.clearAll()
        Task { await HoistObservable.shared.tick() }
    }

    /// A snapshot of every active override.
    public static var overrides: [String: AttributeValue] {
        storage.withLock { $0.overrides }
    }

    /// `true` if `key` currently has an override.
    public static func isOverridden(_ key: String) -> Bool {
        storage.withLock { $0.overrides[key] != nil }
    }
}
