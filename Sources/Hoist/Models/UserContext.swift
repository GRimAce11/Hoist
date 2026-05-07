import Foundation

/// Facts about the current user, used by the evaluator to match rules.
///
/// `userID` is also used as the bucketing key for percentage rollouts and A/B splits.
/// If `userID` is `nil`, rollout and split rules are skipped (the evaluator falls through).
public struct UserContext: Sendable, Equatable {
    public var userID: String?
    public var attributes: [String: AttributeValue]

    public init(
        userID: String? = nil,
        attributes: [String: AttributeValue] = [:]
    ) {
        self.userID = userID
        self.attributes = attributes
    }

    /// A context with no user identity and no attributes.
    public static let anonymous = UserContext()
}
