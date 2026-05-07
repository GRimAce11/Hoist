# ``Hoist``

A lightweight, type-safe feature-flag library for Swift apps — pure Swift, zero dependencies, self-hostable.

## Overview

Hoist gives you the everyday primitives you'd reach for in LaunchDarkly or Firebase Remote Config — gradual rollouts, A/B splits, targeted rules, runtime overrides, a debug overlay — in roughly 1,100 lines of pure Swift, with no third-party dependencies and a single SwiftUI property wrapper as the day-to-day API.

```swift
@FeatureFlag("new_checkout") var useNewCheckout

if useNewCheckout {
    NewCheckoutView()
} else {
    LegacyCheckoutView()
}
```

### Configure once

Load a flag document at app launch and supply a ``UserContext`` describing the current user:

```swift
try await Hoist.configure(
    source: .bundled(filename: "flags.json"),
    context: UserContext(
        userID: user.id,
        attributes: ["country": .string("US"), "plan": .string("pro")]
    )
)
```

The configuration source is one of three ``FlagSource`` cases — ``FlagSource/bundled(filename:bundle:)``, ``FlagSource/data(_:)``, or ``FlagSource/url(_:)``. If the load fails, every read returns its per-call default and the app keeps working.

### Read flag values

From SwiftUI, use the ``FeatureFlag`` property wrapper. From plain Swift / UIKit, call ``Hoist/bool(_:default:)``, ``Hoist/int(_:default:)``, ``Hoist/double(_:default:)``, or ``Hoist/string(_:default:)``.

```swift
struct CheckoutView: View {
    @FeatureFlag("new_checkout") var useNewCheckout
    @FeatureFlag("max_upload_mb", default: 10) var maxMB
    var body: some View { /* … */ }
}
```

Reads are synchronous and thread-safe. Views observing a flag re-render automatically when ``Hoist/configure(source:context:)``, ``Hoist/update(context:)``, ``Hoist/reset()``, or any override mutates state.

### Rules

A flag has a `default` and an ordered list of `rules`. The evaluator walks rules **top to bottom** and returns the first match. Three rule kinds:

- **`if`** — all key/value pairs must match the user's context (AND).
- **`rollout`** — match if `SHA-256(flagKey + ":" + userID) % 100 < percentage`.
- **`split`** — deterministically pick a variant by weight; the variant string becomes the value.

Operators inside `if`: `eq`, `neq`, `in`, `notIn`, `gt`, `gte`, `lt`, `lte`, `contains`, `startsWith`, `endsWith`. A bare value (`{ "country": "US" }`) is sugar for `eq`.

### Runtime overrides

Force any flag to a specific value, bypassing rule evaluation. Persisted to a dedicated `UserDefaults` suite (`com.hoist.overrides`) so overrides survive app launches.

```swift
Hoist.override("new_checkout", with: true)
Hoist.clearOverride("new_checkout")
Hoist.clearAllOverrides()
```

Resolution order: **override → rule → default**.

### Debug overlay

``HoistDebugView`` is a drop-in SwiftUI screen that lists every flag with a type-aware editor, search, and per-flag reset. Present it however your app prefers — a debug menu, shake gesture, hidden tap target.

## Topics

### Configuring Hoist

- ``Hoist/configure(source:context:)``
- ``Hoist/update(context:)``
- ``Hoist/reset()``
- ``FlagSource``
- ``UserContext``
- ``AttributeValue``

### Reading flags

- ``FeatureFlag``
- ``Hoist/bool(_:default:)``
- ``Hoist/int(_:default:)``
- ``Hoist/double(_:default:)``
- ``Hoist/string(_:default:)``
- ``FlagValue``

### Runtime overrides

- ``Hoist/override(_:with:)``
- ``Hoist/clearOverride(_:)``
- ``Hoist/clearAllOverrides()``
- ``Hoist/overrides``
- ``Hoist/isOverridden(_:)``

### Debug UI

- ``HoistDebugView``
- ``HoistObservable``

### Rule model

- ``Flag``
- ``FlagType``
- ``FlagDocument``
- ``FlagRegistry``
- ``Rule``
- ``Condition``
- ``ConditionOperator``
- ``SplitVariant``

### Articles

- <doc:Architecture>
