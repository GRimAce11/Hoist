import SwiftUI

/// A SwiftUI property wrapper for reading a Hoist flag inside a `View` body.
///
/// ```swift
/// struct CheckoutView: View {
///     @FeatureFlag("new_checkout", default: false) var useNewCheckout
///     @FeatureFlag("home_layout", default: "grid") var layout
///
///     var body: some View {
///         if useNewCheckout { NewCheckoutView() } else { OldCheckoutView() }
///     }
/// }
/// ```
///
/// The view automatically re-renders when `Hoist.configure(...)`,
/// `Hoist.update(context:)`, or `Hoist.reset()` is called.
@propertyWrapper
public struct FeatureFlag<Value: FlagValue>: DynamicProperty {
    public let key: String
    public let defaultValue: Value

    public init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    @MainActor
    public var wrappedValue: Value {
        // Establish the observation dependency on the shared model so that
        // any mutation of `version` triggers a SwiftUI re-render.
        _ = HoistObservable.shared.version
        return Value._hoistRead(key: key, default: defaultValue)
    }
}

extension FeatureFlag where Value == Bool {
    /// Convenience initializer for boolean flags with a `false` default.
    public init(_ key: String) {
        self.init(key, default: false)
    }
}
