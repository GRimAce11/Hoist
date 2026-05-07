import Foundation

/// The declared type of a flag in the configuration document.
public enum FlagType: String, Sendable, Codable {
    case bool
    case int
    case double
    case string
}
