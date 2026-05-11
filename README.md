<h1 align="center">Hoist</h1>

<p align="center">
  <strong>Feature flags for Swift apps — pure Swift, zero dependencies, self-hostable.</strong><br/>
  Roll out features gradually, A/B test, target users, and ship kill switches — without an App Store release.
</p>

<p align="center">
  <a href="https://github.com/GRimAce11/Hoist/actions/workflows/ci.yml"><img src="https://github.com/GRimAce11/Hoist/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://swiftpackageindex.com/GRimAce11/Hoist"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FGRimAce11%2FHoist%2Fbadge%3Ftype%3Dswift-versions" alt="Swift versions"></a>
  <a href="https://swiftpackageindex.com/GRimAce11/Hoist"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FGRimAce11%2FHoist%2Fbadge%3Ftype%3Dplatforms" alt="Platforms"></a>
  <a href="https://github.com/GRimAce11/Hoist/blob/main/LICENSE"><img src="https://img.shields.io/github/license/GRimAce11/Hoist" alt="License"></a>
  <a href="https://swiftpackageindex.com/GRimAce11/Hoist/documentation/hoist"><img src="https://img.shields.io/badge/docs-DocC-blue" alt="Documentation"></a>
</p>

---

## What is Hoist?

Hoist is an open-source, MIT-licensed feature-flag library for iOS, macOS, tvOS, watchOS, and visionOS. It gives you the everyday primitives you'd reach for in LaunchDarkly or Firebase Remote Config — gradual rollouts, A/B splits, targeted rules, runtime overrides, a debug overlay — in roughly 1,100 lines of pure Swift, with no third-party dependencies and a single SwiftUI property wrapper as the day-to-day API.

```swift
@FeatureFlag("new_checkout") var useNewCheckout

if useNewCheckout {
    NewCheckoutView()
} else {
    LegacyCheckoutView()
}
```

## Why Hoist?

| | Hoist | LaunchDarkly | Statsig | ConfigCat | Firebase&nbsp;Remote&nbsp;Config |
|---|:-:|:-:|:-:|:-:|:-:|
| Pure Swift | ✅ | ❌ | ❌ | ❌ | ❌ |
| Zero third-party deps | ✅ | ❌ | ❌ | ❌ | ❌ |
| Open source (MIT) | ✅ | ❌ | ❌ | ✅ | ❌ |
| Self-hostable | ✅ | ❌ | ❌ | ⚠️ | ❌ |
| Swift 6 strict concurrency | ✅ | ❌ | ❌ | ❌ | ❌ |
| `@Observable` / native SwiftUI | ✅ | ⚠️ | ❌ | ❌ | ❌ |
| Built-in debug overlay | ✅ | ✅ | ✅ | ⚠️ | ❌ |
| Runtime overrides | ✅ | ✅ | ✅ | ⚠️ | ⚠️ |
| Free tier | ∞ | seats-based | yes | yes | yes |
| Vendor lock-in | none | high | high | medium | high |

**Pick Hoist when** you want a small, auditable, self-hostable flag layer that integrates naturally with modern SwiftUI and doesn't require an account, an SDK initialiser, or a $200K/yr contract.

**Pick something else when** you need a managed dashboard, automated experiment statistics, multi-team approvals, audit logs, or sub-second push updates from a managed cloud — those are problems best solved by paid platforms.

## Requirements

| Swift | iOS | macOS | tvOS | watchOS | visionOS |
|:-:|:-:|:-:|:-:|:-:|:-:|
| 6.0+ | 17+ | 14+ | 17+ | 10+ | 1.0+ |

## Installation

### Swift Package Manager

Add Hoist to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/Hoist", from: "0.2.0"),
],
targets: [
    .target(name: "MyApp", dependencies: ["Hoist"]),
]
```

Or in Xcode: **File → Add Package Dependencies…** and paste
`https://github.com/GRimAce11/Hoist`.

## Quick start

### 1. Bundle a `flags.json` with your app

```json
{
  "schemaVersion": 1,
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
        { "if": { "plan": { "in": ["pro", "team"] } }, "value": 100 }
      ]
    }
  }
}
```

> `schemaVersion` is optional today — documents without it are treated as v1.
> Declaring it explicitly is recommended so future format bumps fail loudly
> instead of silently misbehaving.

### 2. Configure once at launch

```swift
import SwiftUI
import Hoist

@main
struct MyApp: App {
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady { RootView() } else { LoadingView() }
            }
            .task {
                do {
                    try await Hoist.configure(
                        source: .bundled(filename: "flags.json"),
                        context: UserContext(
                            userID: UserSession.current.id,
                            attributes: [
                                "country": .string(Locale.current.region?.identifier ?? "??"),
                                "plan":    .string(UserSession.current.plan),
                            ]
                        )
                    )
                } catch {
                    // Hoist returns the per-call default for every read on failure;
                    // the app keeps working with safe defaults.
                    print("Hoist configure failed: \(error)")
                }
                isReady = true
            }
        }
    }
}
```

### 3. Read flags anywhere

```swift
// SwiftUI
struct CheckoutView: View {
    @FeatureFlag("new_checkout") var useNewCheckout
    @FeatureFlag("max_upload_mb", default: 10) var maxMB

    var body: some View {
        if useNewCheckout {
            NewCheckoutView(uploadLimit: maxMB)
        } else {
            LegacyCheckoutView()
        }
    }
}

// Plain Swift
if Hoist.bool("new_checkout") {
    showNewCheckout()
}
let limit = Hoist.int("max_upload_mb", default: 10)
```

When `Hoist.configure(...)`, `Hoist.update(context:)`, or any override changes, every `@FeatureFlag` view re-renders automatically — Observation tracks the dependency.

## Concepts

### Rules

A flag has a `default` and an ordered list of `rules`. The evaluator walks rules **top to bottom** and returns the first match. Three rule kinds:

| Rule | Behaviour |
|---|---|
| `if` | All key/value pairs must match the user's context (AND). |
| `rollout` | Match if `SHA-256(flagKey + ":" + userID) % 100 < percentage`. |
| `split` | Deterministically pick a variant by weight. The variant string becomes the value. |

```json
"rules": [
  { "if": { "isInternal": true }, "value": true },
  { "if": { "country": { "in": ["US", "CA"] } }, "value": true },
  { "rollout": 25, "value": true }
]
```

Operators inside `if`: `eq`, `neq`, `in`, `notIn`, `gt`, `gte`, `lt`, `lte`, `contains`, `startsWith`, `endsWith`. A bare value (`{ "country": "US" }`) is sugar for `eq`.

### Deterministic rollouts

Bucketing uses `SHA-256("<flagKey>:<userID>")` reduced modulo 100. The same user always lands in the same bucket for the same flag, so a user never flickers between variants on relaunch.

A `userID` is required for `rollout` and `split` rules. Use a stable per-install UUID in Keychain if you don't have a logged-in user.

### Remote sources and background refresh

`FlagSource.url(_:pollInterval:)` fetches a JSON document over HTTPS. Pass a
`pollInterval` to keep it fresh: Hoist spawns a cancellable background task
that refetches every N seconds, sending `If-None-Match` with the cached
`ETag` so an unchanged document costs ~200 bytes per check.

```swift
try await Hoist.configure(
    source: .layered([
        .bundled(filename: "flags.json"),                               // floor
        .url(URL(string: "https://flags.acme.com/ios.json")!,
             pollInterval: 60),                                          // override + refresh
    ]),
    context: UserContext(userID: user.id, attributes: [...])
)
```

- Bundled defaults are always available offline, so reads keep working when
  the network is down or your endpoint is 5xx-ing.
- The remote layer fills in / overrides keys per `schemaVersion` merge rules.
- Polling stops automatically on the next `Hoist.configure(...)` or
  `Hoist.reset()`.
- Have your endpoint set `Cache-Control: no-cache, must-revalidate` and emit
  a strong `ETag` to get the 304 short-circuit. CDNs like Cloudflare and
  Fastly do this for static files automatically.

### Runtime overrides

Force any flag to a specific value, bypassing rule evaluation. Persisted to a dedicated `UserDefaults` suite (`com.hoist.overrides`), so overrides survive app launches.

```swift
Hoist.override("new_checkout", with: true)       // force ON
Hoist.override("max_upload_mb", with: 500)
Hoist.override("home_layout",   with: "carousel")

Hoist.clearOverride("new_checkout")              // back to rules
Hoist.clearAllOverrides()
```

Resolution order: **override → rule → default**.

### Debug overlay

Drop in a SwiftUI screen that lists every flag with a type-aware editor, search, and per-flag reset:

```swift
import Hoist

struct RootView: View {
    @State private var showFlags = false

    var body: some View {
        ContentView()
            #if DEBUG
            .toolbar {
                ToolbarItem {
                    Button("Flags") { showFlags = true }
                }
            }
            .sheet(isPresented: $showFlags) { HoistDebugView() }
            #endif
    }
}
```

> **Tip:** Pair it with a shake-gesture, a triple-tap, or a hidden settings entry. Hoist deliberately doesn't ship a gesture trigger so you can present `HoistDebugView` however your app prefers.

## Integrations

### UIKit

Hoist is SwiftUI-native but the core API is plain Swift, so UIKit works fine:

```swift
import UIKit
import Hoist

final class CheckoutViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        if Hoist.bool("new_checkout") {
            installNewCheckoutFlow()
        } else {
            installLegacyFlow()
        }
    }
}

// To present the debug overlay:
let host = UIHostingController(rootView: HoistDebugView())
present(host, animated: true)
```

### Testing

Configure Hoist with inline JSON at the start of each test for full determinism:

```swift
import Testing
@testable import MyApp
import Hoist

@Test func showsNewCheckoutForUSUsers() async throws {
    let json = #"""
    { "flags": { "new_checkout": {
        "type": "bool", "default": false,
        "rules": [{ "if": { "country": "US" }, "value": true }]
    }}}
    """#
    await Hoist.reset()
    try await Hoist.configure(
        source: .data(Data(json.utf8)),
        context: UserContext(userID: "test", attributes: ["country": .string("US")])
    )

    #expect(Hoist.bool("new_checkout") == true)
}
```

For tests that want a hard-coded value regardless of rules, use `Hoist.override(_:with:)`.

> **Note:** Hoist holds a single global state. If you run tests in parallel across multiple suites that touch `Hoist.configure(...)`, group them under a single `.serialized` parent suite so they don't race.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Public API — Hoist.configure / .bool / .int / @FeatureFlag         │
└──────────────────┬──────────────────────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
┌──────────────┐      ┌────────────────────────────┐
│  Resolve     │      │  HoistObservable           │
│  (sync, lock)│      │  (@MainActor @Observable)  │
└─────┬────────┘      └────────────────────────────┘
      │ override → rule → default
      ▼
┌────────────────────────────────────────────┐
│  Evaluator (pure function, no I/O)         │
│  ├─ Condition rules (11 operators)         │
│  ├─ Rollout rules (SHA-256 bucketing)      │
│  └─ Split rules (weighted variants)        │
└────────────────────────────────────────────┘
```

**Highlights**

- Pure-function evaluator — no I/O, no shared state, fully deterministic
- Lock-protected snapshot via `OSAllocatedUnfairLock<Storage>`
- Async loaders (`bundled` / `data` / `url`) on top of structured concurrency
- `@Observable` SwiftUI bridge for re-rendering
- Persistent overrides stored in a dedicated `UserDefaults` suite

The full architecture article ships with the package — open the [DocC catalog](https://swiftpackageindex.com/GRimAce11/Hoist/documentation/hoist) for the deeper dive, or read [`Sources/Hoist/Hoist.docc/Architecture.md`](Sources/Hoist/Hoist.docc/Architecture.md) directly.

## Examples

A complete reference app and a comprehensive sample `flags.json` live under [`Examples/`](Examples/):

- [`Examples/flags.json`](Examples/flags.json) — every rule kind and operator in one document.
- [`Examples/SampleApp.swift`](Examples/SampleApp.swift) — minimal SwiftUI app wired to Hoist with a debug overlay.
- [`Examples/UIKitUsage.swift`](Examples/UIKitUsage.swift) — UIKit `UIViewController` reading flags and presenting `HoistDebugView`.
- [`Examples/TestingExample.swift`](Examples/TestingExample.swift) — Swift Testing pattern: `reset` → `configure(.data(...))` → assert.

## Limitations

Hoist is a small, focused library. Things it deliberately does **not** do yet:

- **No exposure events.** Variant assignments are not reported anywhere by
  default, so A/B-test attribution requires your own glue code.
  `Hoist.onEvaluate` is planned for v0.3.
- **No managed dashboard.** Author flags in JSON and ship the file yourself
  (bundle, S3, your own backend). If you want a UI to flip flags without
  committing JSON, reach for LaunchDarkly / Statsig / ConfigCat.
- **No sub-second propagation.** Server-Sent Events / push transport is on
  the v1.0 roadmap. Today the floor is "how often does your app re-call
  `Hoist.configure(...)`."

If one of these is a hard blocker, the v0.3 roadmap below is where to look —
or open an issue and we'll see if it can move up.

## Roadmap

- [x] Pure-function evaluator with `if` / `rollout` / `split` rules
- [x] 11 condition operators (eq, neq, in, notIn, gt, gte, lt, lte, contains, startsWith, endsWith)
- [x] SHA-256 deterministic bucketing
- [x] Bundled / data / remote JSON sources
- [x] `@FeatureFlag` SwiftUI property wrapper
- [x] Persistent runtime overrides
- [x] `HoistDebugView` debug overlay
- [x] DocC documentation catalog
- [x] Multi-platform CI
- [x] Versioned document schema (`schemaVersion`) with explicit upgrade errors
- [x] Layered sources (`.layered([.bundled(...), .url(...)])`) — in progress on `main`
- [x] Background polling + ETag caching on `.url` sources — in progress on `main`
- [ ] **v0.3** — Analytics exposure hook for A/B test attribution
- [ ] **v1.0** — CLI for linting and managing `flags.json`
- [ ] **v1.0** — Server-Sent Events transport for sub-second updates
- [ ] **v1.0** — Optional reference server (Vapor) for self-hosting

## Contributing

Issues, PRs, and discussions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Chethan Nayak
