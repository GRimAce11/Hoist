import Foundation
import Observation

/// Observable model that SwiftUI views subscribe to so they re-render when
/// Hoist's flag configuration changes.
///
/// You normally don't interact with this directly — `@FeatureFlag` does it for you.
@Observable
@MainActor
public final class HoistObservable {
    public static let shared = HoistObservable()

    /// Incremented whenever Hoist's flags or context change.
    /// Reading this inside a SwiftUI body establishes the observation dependency.
    public private(set) var version: UInt64 = 0

    private init() {}

    func tick() {
        version &+= 1
    }
}
