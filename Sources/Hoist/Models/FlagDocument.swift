import Foundation

/// The top-level structure of a Hoist JSON configuration file.
///
/// ```json
/// {
///   "flags": {
///     "<flagKey>": { "type": "bool", "default": false, "rules": [...] }
///   }
/// }
/// ```
public struct FlagDocument: Sendable, Decodable {
    public let flags: [String: Flag]

    public init(flags: [String: Flag]) {
        self.flags = flags
    }
}
