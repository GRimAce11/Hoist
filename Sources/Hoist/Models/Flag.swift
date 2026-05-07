import Foundation

/// A single feature flag definition.
///
/// A `Flag` carries a declared ``FlagType``, a `defaultValue` returned when no
/// rule matches, and an ordered list of ``Rule`` instances. The evaluator walks
/// `rules` top-to-bottom and returns the value of the first rule that fires.
///
/// `Flag` instances are normally produced by decoding a ``FlagDocument`` rather
/// than constructed directly — but the memberwise initializer is public to
/// support unit tests and synthetic in-memory flag sources.
public struct Flag: Sendable, Equatable {
    public let key: String
    public let type: FlagType
    public let defaultValue: AttributeValue
    public let rules: [Rule]

    public init(
        key: String,
        type: FlagType,
        defaultValue: AttributeValue,
        rules: [Rule] = []
    ) {
        self.key = key
        self.type = type
        self.defaultValue = defaultValue
        self.rules = rules
    }
}

extension Flag: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case `default`
        case rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(FlagType.self, forKey: .type)
        let defaultValue = try container.decode(AttributeValue.self, forKey: .default)
        let rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []

        // Decoder's coding path's last key is the flag's name in the parent dictionary.
        let key = decoder.codingPath.last?.stringValue ?? ""

        self.init(key: key, type: type, defaultValue: defaultValue, rules: rules)
    }
}
