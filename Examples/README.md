# Hoist examples

Reference snippets and sample data for getting Hoist into a real app. Files in this folder are **documentation only** — they're not part of the library target and are not compiled by SwiftPM.

| File | What it shows |
|---|---|
| [`flags.json`](flags.json) | Comprehensive flag document covering every rule kind and operator. Drop it into your app bundle to play with the API. |
| [`SampleApp.swift`](SampleApp.swift) | Minimal SwiftUI app: configures Hoist at launch, reads a flag with `@FeatureFlag`, and exposes the debug overlay behind `#if DEBUG`. |
| [`UIKitUsage.swift`](UIKitUsage.swift) | UIKit equivalent — reads flags from a `UIViewController` and presents `HoistDebugView` with `UIHostingController`. |
| [`TestingExample.swift`](TestingExample.swift) | Swift Testing snippet showing the recommended pattern: `Hoist.reset()` → `Hoist.configure(.data(...))` → assert. |

## Suggested adoption path

1. Copy `flags.json` into your app bundle and trim it to the flags you actually need.
2. Adapt `SampleApp.swift` — replace `UserSession.current` with whatever your app uses for the logged-in user.
3. Wrap any flag read site with the property wrapper (SwiftUI) or `Hoist.bool/int/double/string` (UIKit, AppKit, plain Swift).
4. For tests, copy the `Hoist.reset()` + `Hoist.configure(.data(...))` pattern from `TestingExample.swift` and remember to put runtime-touching tests inside a `.serialized` parent suite — Hoist holds a single global state.
