import Foundation

/// The top-level structure of a Hoist JSON configuration file.
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "flags": {
///     "<flagKey>": { "type": "bool", "default": false, "rules": [...] }
///   }
/// }
/// ```
///
/// `schemaVersion` is optional. When absent, the document is assumed to
/// conform to schema version `1` (the original Hoist format). When present,
/// it must be one of `Hoist.supportedSchemaVersions` or loading fails with
/// `FlagSourceError.unsupportedSchemaVersion`.
public struct FlagDocument: Sendable, Decodable {
    /// The schema version declared by the document. `nil` means "unspecified"
    /// and is treated as `1` for compatibility with pre-0.2.2 files.
    public let schemaVersion: Int?
    public let flags: [String: Flag]

    public init(schemaVersion: Int? = nil, flags: [String: Flag]) {
        self.schemaVersion = schemaVersion
        self.flags = flags
    }
}

extension FlagDocument {
    /// The schema version after applying the "absent means 1" default.
    var resolvedSchemaVersion: Int { schemaVersion ?? 1 }
}
