import Foundation

/// Marker protocol for Swift types that can be used as flag values.
///
/// Conformed to by `Bool`, `Int`, `Double`, and `String`. The `_read` requirement
/// is an implementation detail used by the `@FeatureFlag` property wrapper —
/// you should not call it directly.
public protocol FlagValue: Sendable, Equatable {
    /// Reads the flag value from the active Hoist configuration.
    /// - Parameters:
    ///   - key: The flag key.
    ///   - defaultValue: Returned if the flag is missing or fails to evaluate.
    static func _hoistRead(key: String, default defaultValue: Self) -> Self
}

extension Bool: FlagValue {
    public static func _hoistRead(key: String, default defaultValue: Bool) -> Bool {
        Hoist.bool(key, default: defaultValue)
    }
}

extension Int: FlagValue {
    public static func _hoistRead(key: String, default defaultValue: Int) -> Int {
        Hoist.int(key, default: defaultValue)
    }
}

extension Double: FlagValue {
    public static func _hoistRead(key: String, default defaultValue: Double) -> Double {
        Hoist.double(key, default: defaultValue)
    }
}

extension String: FlagValue {
    public static func _hoistRead(key: String, default defaultValue: String) -> String {
        Hoist.string(key, default: defaultValue)
    }
}
