# Changelog

All notable changes to Hoist are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Gated `rollout` and `split` rules.** A rule may now combine `if` with
  `rollout` or `split` in a single object — conditions are evaluated first
  (AND), and only matching users are bucketed:
  ```json
  { "if": { "country": { "in": ["US","CA"] } }, "rollout": 25, "value": true }
  { "if": { "plan": "pro" }, "split": { "a": 50, "b": 50 } }
  ```
  Previously the same effect required either two separate rules (which
  unintentionally rolled out to non-matching users via the catch-all) or
  call-site filtering of the `UserContext`.

  The bucketing key is unchanged (`"<flagKey>:<userID>"`); gating attributes
  do not enter the hash, so widening a gated rollout only adds users — it
  never reshuffles existing ones.

### Changed

- **Source-breaking**: `Rule.rollout` and `Rule.split` now carry a
  `conditions: [Condition]` associated value. Convenience static factories
  (`Rule.rollout(percentage:value:)`, `Rule.split(variants:)`) preserve the
  un-gated construction sites. Pattern matchers on
  `case .rollout(let p, let v)` must become `case .rollout(_, let p, let v)`
  (or destructure the new `conditions` slot). Acceptable in 0.x.

### Tests

- 7 new tests covering gated rollout match, gate-fail fall-through,
  no-userID skip while gate matches, ~25% distribution within a US-gated
  subset (with non-US users verified to never hit), gated split, and two
  decoder round-trips for `if`+`rollout` and `if`+`split`. 84/84 total
  tests passing.

## [0.4.0] — 2026-05-11

A robustness pass on the v0.3 features after a brutally honest internal
review surfaced production-readiness gaps. No new product surface beyond
auth headers and exposure dedup — mostly making the existing polling and
analytics pipeline behave correctly under real network conditions and
real-app read volumes.

### Added

- **Polling jitter and exponential backoff.** The background refresh loop
  on `.url(_, pollInterval:)` now sleeps for `interval × backoff × jitter`
  where `backoff` doubles on each consecutive failure (capped at 16×) and
  `jitter` is a fresh random in `0.9...1.1` per cycle. Prevents thundering
  herds on minute boundaries and protects flapping endpoints. Backoff
  resets on the first successful refresh.
- **`Hoist.exposureDedup: ExposureDedup`.** Controls whether `onEvaluate`
  fires on every public read (`.everyRead`) or once per unique
  `(flagKey, userID, value, source)` until the next configure/reset
  (`.perSession`, the new default). Important for analytics cost control —
  a single SwiftUI body might call `Hoist.bool(...)` dozens of times per
  render.
- **Auth headers on `.url`.** `FlagSource.url(URL, headers: [String: String] = [:], pollInterval: TimeInterval? = nil)`.
  Headers are applied to every fetch (initial and polled), with the cached
  `If-None-Match` header layered on top unless the caller has already set
  one. Enables bearer-token endpoints, signed-URL metadata, and similar
  auth patterns.
- **`Hoist.urlSession`** as an internal `URLSession` seam tests can swap
  via `@testable import`. Defaults to `URLSession.shared`. Enables real
  integration tests of the polling refresh loop, ETag short-circuit, and
  auth-header behavior using `URLProtocol` stubs.

### Changed

- **Source-breaking** (third and final time for v0.3.x churn):
  `FlagSource.url(URL, pollInterval:)` is now `FlagSource.url(URL, headers: [String: String] = [:], pollInterval: TimeInterval? = nil)`.
  Constructor sites with `pollInterval:` and `headers:` keep working
  because both have defaults. Pattern matchers on `case .url(let u, _)`
  need a third placeholder: `case .url(let u, _, _)`. The v0.3.0 pattern
  matcher form will not compile against v0.4.0.

### Tests

- 7 new tests: 4 cover `ExposureDedup` (per-session collapse, value-change
  refire, `.everyRead` opt-out, configure-resets-session) and 3 cover the
  URLProtocol-stubbed integration paths (polling actually refetches +
  updates registry, auth headers reach the wire, ETag 304 returns the
  cached document). 77/77 total tests passing.

## [0.3.0] — 2026-05-11

### Added

- `FlagSource.layered([FlagSource])`: ordered fallback chain with per-key
  overlay merge — later layers override earlier per flag key, individual
  layer failures are tolerated, and all-fail rethrows the last error.
  Typical shape: `.layered([.bundled("defaults.json"), .url(remote)])`.
- Background polling on `FlagSource.url`: payload now takes a
  `pollInterval: TimeInterval?` and Hoist spawns a cancellable refresh task
  when the value is non-nil. Each refresh sends `If-None-Match` with the
  cached `ETag` and short-circuits on a `304 Not Modified`. Polling is
  scoped per source: a `.url` nested inside `.layered(...)` triggers a
  refresh of the whole chain at the shortest declared interval.
- `Hoist.onEvaluate` exposure hook for A/B-test attribution. Fires once per
  public read (`bool` / `int` / `double` / `string`) with the served value
  and where it came from. Source taxonomy: `.override`, `.rule(index:)`,
  `.defaultValue`, `.fallback`.
- New public types `EvaluationEvent` and `EvaluationSource` (in
  `Sources/Hoist/Models/EvaluationEvent.swift`).
- Internal `Evaluator.evaluateDetailed(_:context:)` that returns the matched
  rule index alongside the value so the exposure hook can populate it.

### Changed

- **Source-breaking**: `FlagSource.url(URL)` is now `FlagSource.url(URL, pollInterval: TimeInterval? = nil)`.
  Constructor sites continue to compile (`.url(url)` still works);
  pattern matchers on `case .url(let u)` must add a placeholder for the new
  payload: `case .url(let u, _)`. Acceptable in 0.x.

## [0.2.2] — 2026-05-11

### Added
- Versioned flag-document schema. `FlagDocument` now decodes an optional
  top-level `schemaVersion: Int`. Documents that omit it are treated as
  version `1` for backwards compatibility; documents that declare a value
  outside `Hoist.supportedSchemaVersions` fail to load with the new
  `FlagSourceError.unsupportedSchemaVersion(found:supported:)`.
- `Hoist.currentSchemaVersion` and `Hoist.supportedSchemaVersions` constants
  so apps can pin or surface the version they target.
- `Examples/flags.json` and the test fixture now declare `"schemaVersion": 1`
  as the recommended shape for new documents.

## [0.2.1] — 2026-05-07

### Added
- DocC documentation catalog (`Sources/Hoist/Hoist.docc`) with a package
  overview and an Architecture article covering storage, resolution order,
  the evaluator, and the SwiftUI bridge.
- `.spi.yml` so Swift Package Index hosts the generated DocC docs.
- Multi-platform CI: matrix job validates the package builds for iOS, tvOS,
  watchOS, and visionOS via `xcodebuild`, alongside the existing
  `swift test` job on macOS.
- `Examples/` folder with a comprehensive reference `flags.json`, a SwiftUI
  sample app, a UIKit snippet, and a Swift Testing snippet.
- Expanded inline doc comments on `Hoist.bool/int/double/string`,
  `AttributeValue`, `Flag`, and `FlagSource` for richer Xcode quick help.

### Changed
- README polished: corrected operator count (10 → 11) in the architecture
  diagram and roadmap, removed broken `<doc:Architecture>` link (now an
  actual DocC article), removed broken `CODE_OF_CONDUCT.md` link, and added
  a pointer to `Examples/`.

### Fixed
- CHANGELOG `[0.1.0]` entry corrected from "10 condition operators" to 11.

## [0.2.0] — 2026-05-07

### Added
- Persistent runtime overrides via `Hoist.override(_:with:)`,
  `clearOverride(_:)`, `clearAllOverrides()`, `overrides`, and
  `isOverridden(_:)`. Overrides are stored in a dedicated `UserDefaults` suite
  (`com.hoist.overrides`) and reloaded on every `configure(...)`.
- `HoistDebugView` — drop-in SwiftUI overlay that lists every flag with a
  type-aware editor, search, and per-flag reset.
- `Hoist.flag(for:)` for debug-UI introspection.

### Changed
- Resolution order is now **override → rule → default**.
- `PublicAPITests` and `OverrideTests` consolidated into a single `.serialized`
  parent suite to prevent cross-suite parallelism from racing on global state.

## [0.1.0] — 2026-05-07

### Added
- Pure-function evaluator with `if`, `rollout`, and `split` rule kinds.
- 11 condition operators: `eq`, `neq`, `in`, `notIn`, `gt`, `gte`, `lt`, `lte`,
  `contains`, `startsWith`, `endsWith`.
- SHA-256 deterministic bucketing for stable percentage rollouts and A/B splits.
- JSON loader supporting bundled, in-memory, and remote sources.
- `@FeatureFlag` SwiftUI property wrapper with Observation-based reactivity.
- Swift 6 strict concurrency, zero third-party dependencies.

[Unreleased]: https://github.com/GRimAce11/Hoist/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/GRimAce11/Hoist/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/GRimAce11/Hoist/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/GRimAce11/Hoist/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/GRimAce11/Hoist/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/GRimAce11/Hoist/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/GRimAce11/Hoist/releases/tag/v0.1.0
