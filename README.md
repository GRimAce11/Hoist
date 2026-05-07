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

```swift
.package(url: "https://github.com/sumitghosh/Hoist", from: "0.1.0")
```

Then add `"Hoist"` to your target's dependencies.

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
- [ ] Core models (Flag, Rule, UserContext)
- [ ] Pure-function evaluator with deterministic bucketing
- [ ] JSON source loaders (bundled, remote)
- [ ] SwiftUI `@FeatureFlag` property wrapper
- [ ] Observation-based reactivity for hot reload
- [ ] Debug overlay for toggling flags at runtime
- [ ] CLI for managing flag config

## License

MIT — see [LICENSE](LICENSE).
