import Foundation

/// Controls how often `Hoist.onEvaluate` fires for the same effective
/// assignment.
///
/// `perSession` (the default) collapses repeated reads of the same flag for
/// the same user that resolve to the same value and source — important for
/// A/B-test cost control, since a single SwiftUI body might call
/// `Hoist.bool(...)` dozens of times per render and you do not want to pay
/// for dozens of identical exposure events. The dedup set is cleared on
/// every `Hoist.configure(...)` and `Hoist.reset()`.
///
/// `everyRead` fires the hook on every public read with no deduplication —
/// useful if you want telemetry on per-call frequency or are wiring
/// `onEvaluate` into a debug stream rather than analytics.
public enum ExposureDedup: Sendable, Hashable {
    case perSession
    case everyRead
}

/// Where a resolved flag value came from.
///
/// Returned via `EvaluationEvent.source` and consumed by `Hoist.onEvaluate`
/// listeners (typically to attribute A/B-test variants in analytics).
public enum EvaluationSource: Sendable, Hashable {
    /// A runtime override was set with `Hoist.override(_:with:)` and won.
    case override

    /// Rule at this index inside the flag's `rules` array matched. The index
    /// is what A/B-test variant attribution joins on — record it alongside
    /// the flag key in your analytics event.
    case rule(index: Int)

    /// The flag exists and was evaluated, but no rule matched, so the flag's
    /// declared `default` was served.
    case defaultValue

    /// The served value did not come from Hoist's evaluator. Either the flag
    /// key is not defined in the loaded document, or the resolved value
    /// could not be coerced to the requested Swift type, so the
    /// caller-supplied `default:` was returned instead.
    case fallback
}

/// A single flag evaluation, emitted to `Hoist.onEvaluate` for every public
/// read (`Hoist.bool`, `Hoist.int`, `Hoist.double`, `Hoist.string`).
///
/// Use this to ship variant attribution events into your analytics pipeline
/// (Amplitude, Mixpanel, Segment, BigQuery, …). The `flagKey` + rule index
/// pair is the natural join key against downstream conversion events.
public struct EvaluationEvent: Sendable, Hashable {
    /// The flag key the caller requested.
    public let flagKey: String

    /// The value Hoist actually served to the caller — i.e. what the call
    /// returned. For type-mismatched or missing flags, this is the
    /// caller-supplied `default`.
    public let value: AttributeValue

    /// Where `value` came from.
    public let source: EvaluationSource

    /// The user ID associated with the evaluation, if the configured
    /// `UserContext` had one. Convenient for joining with downstream events.
    public let userID: String?

    public init(
        flagKey: String,
        value: AttributeValue,
        source: EvaluationSource,
        userID: String?
    ) {
        self.flagKey = flagKey
        self.value = value
        self.source = source
        self.userID = userID
    }
}
