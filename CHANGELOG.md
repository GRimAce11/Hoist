# Changelog

All notable changes to Hoist are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned for 0.3.0
- Remote sync with polling + ETag caching for `FlagSource.url(...)`.
- Layered flag sources (`.layered([.bundled(...), .url(...)])`).
- Analytics exposure hook (`Hoist.onEvaluate`) for A/B-test attribution.

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

[Unreleased]: https://github.com/GRimAce11/Hoist/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/GRimAce11/Hoist/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/GRimAce11/Hoist/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/GRimAce11/Hoist/releases/tag/v0.1.0
