import Foundation

/// Persists feature-flag overrides to a `UserDefaults` suite so they survive
/// app launches. Internal — exposed via `Hoist.override(_:with:)` and friends.
struct OverrideStore: @unchecked Sendable {
    // `UserDefaults` isn't formally Sendable but its public API is documented
    // thread-safe; we're holding it behind read-only access only.
    /// The default `UserDefaults` suite name. Kept in its own suite so overrides
    /// don't pollute your app's standard defaults.
    static let defaultSuiteName = "com.hoist.overrides"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults? = nil,
        key: String = "overrides.v1"
    ) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.defaultSuiteName)
            ?? .standard
        self.key = key
    }

    func load() -> [String: AttributeValue] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: AttributeValue].self, from: data)) ?? [:]
    }

    func save(_ overrides: [String: AttributeValue]) {
        guard !overrides.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(overrides) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    func clearAll() {
        defaults.removeObject(forKey: key)
    }
}
