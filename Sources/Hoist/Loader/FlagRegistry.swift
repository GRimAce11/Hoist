import Foundation

/// An immutable, in-memory snapshot of all parsed flag definitions.
///
/// Built once from a `FlagDocument`, then read concurrently. Lookups are O(1).
public struct FlagRegistry: Sendable, Equatable {
    public let flags: [String: Flag]

    public init(flags: [String: Flag] = [:]) {
        self.flags = flags
    }

    public init(document: FlagDocument) {
        // Each Flag's `key` was set from its dictionary key during decoding,
        // but we re-stamp from the canonical map key here for safety.
        var rebuilt: [String: Flag] = [:]
        rebuilt.reserveCapacity(document.flags.count)
        for (key, flag) in document.flags {
            rebuilt[key] = Flag(
                key: key,
                type: flag.type,
                defaultValue: flag.defaultValue,
                rules: flag.rules
            )
        }
        self.flags = rebuilt
    }

    public func flag(for key: String) -> Flag? {
        flags[key]
    }

    public static let empty = FlagRegistry()
}
