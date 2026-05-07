# Hoist

A lightweight, type-safe feature flag library for Swift.

> Roll out features gradually, A/B test, target users — without shipping a new build.

## Status

Pre-release — under active development. APIs may change.

## Why Hoist?

- **Pure Swift** — no Objective-C, no third-party dependencies, Swift 6 strict concurrency
- **Local or remote** — bundle a JSON file, fetch from your server, or both
- **Deterministic rollouts** — the same user always gets the same variant for a flag
- **SwiftUI native** — `@FeatureFlag` property wrapper with Observation-based updates
- **Privacy-first** — no third-party tracking, nothing leaves the device by default

## Requirements

- Swift 6.0+
- iOS 17 / macOS 14 / tvOS 17 / watchOS 10 / visionOS 1

## Installation

### Swift Package Manager

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/Hoist", from: "0.2.0"),
],
targets: [
    .target(name: "MyApp", dependencies: ["Hoist"]),
]
```

Or in Xcode: **File → Add Package Dependencies** and paste
`https://github.com/GRimAce11/Hoist`.

## Quick start

```swift
import Hoist

// 1. Configure once at app launch
Hoist.configure(
    source: .bundled("flags.json"),
    context: UserContext(
        userID: currentUser.id,
        attributes: [
            "country": .string("US"),
            "plan": .string("pro"),
        ]
    )
)

// 2. Read flag values anywhere
if Hoist.bool("new_checkout") {
    showNewCheckout()
}

let uploadLimit = Hoist.int("max_upload_mb")  // e.g. 100
```

### SwiftUI integration

```swift
struct CheckoutView: View {
    @FeatureFlag("new_checkout") var useNewCheckout
    @FeatureFlag("home_layout", default: "grid") var layout

    var body: some View {
        if useNewCheckout {
            NewCheckoutView()
        } else {
            OldCheckoutView()
        }
    }
}
```

### Runtime overrides

Force a flag to a specific value at runtime — bypasses rule evaluation.
Overrides are persisted to a dedicated `UserDefaults` suite, so they survive
app launches.

```swift
Hoist.override("new_checkout", with: true)     // force ON
Hoist.override("max_upload_mb", with: 500)
Hoist.override("home_layout", with: "carousel")

Hoist.clearOverride("new_checkout")            // back to rules
Hoist.clearAllOverrides()
```

Resolution order: **override → rule → default**.

### Debug overlay

Drop in a SwiftUI debug screen that lists every flag with type-aware editors,
search, and an orange badge on overridden values:

```swift
import Hoist

struct RootView: View {
    @State private var showFlags = false

    var body: some View {
        ContentView()
            #if DEBUG
            .onShakeGesture { showFlags = true }
            .sheet(isPresented: $showFlags) { HoistDebugView() }
            #endif
    }
}
```

The view auto-refreshes whenever a flag is overridden, the context changes,
or `configure(...)` is called again.

## Flag definition format

```json
{
  "flags": {
    "new_checkout": {
      "type": "bool",
      "default": false,
      "rules": [
        { "if": { "country": "US" }, "value": true },
        { "rollout": 25, "value": true }
      ]
    },
    "max_upload_mb": {
      "type": "int",
      "default": 10,
      "rules": [
        { "if": { "plan": "pro" }, "value": 100 }
      ]
    }
  }
}
```

The evaluator walks rules top to bottom and returns the first match. If nothing matches, the `default` is returned.

## Roadmap

- [x] Project scaffold
- [x] Core models (Flag, Rule, UserContext)
- [x] Pure-function evaluator with deterministic bucketing
- [x] JSON source loaders (bundled, data, remote)
- [x] SwiftUI `@FeatureFlag` property wrapper
- [x] Observation-based reactivity for hot reload
- [x] Runtime overrides with persistence
- [x] Debug overlay (`HoistDebugView`)
- [ ] Remote sync with polling and ETag caching
- [ ] Analytics hook for flag-exposure events
- [ ] CLI for managing flag config

## License

MIT — see [LICENSE](LICENSE).
