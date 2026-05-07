# Architecture

How Hoist evaluates a flag, where state lives, and why the design stays small.

## Overview

Hoist is split into four cooperating layers. Each has a single responsibility and a narrow API surface.

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

## Storage

The single source of truth is `Hoist.storage`, an `OSAllocatedUnfairLock<Storage>`. `Storage` holds three things:

- a ``FlagRegistry`` (parsed flag definitions, keyed by flag name)
- the current ``UserContext``
- the override map (`[String: AttributeValue]`)

Every read takes the lock briefly, copies what it needs, and releases. Reads do not block on I/O.

## Resolution order

When you call `Hoist.bool("k")`, the resolver walks three layers in order:

1. **Override.** If `state.overrides["k"]` is set, return it. Overrides bypass rule evaluation entirely.
2. **Rule.** Otherwise, look up the flag in the registry and run the pure-function ``Evaluator`` against the current context.
3. **Default.** If no flag exists with that key, return the per-call default the caller passed.

This means a missing flag never crashes — it falls through to the caller's default. A failed `configure()` leaves the registry empty and the same fallback applies.

## The evaluator

``Evaluator`` is the most-tested layer. It is a pure function: `(Flag, UserContext) -> AttributeValue`. No I/O, no shared state. The evaluator walks `flag.rules` top-to-bottom; the first rule that produces a non-nil value wins, otherwise the flag's `defaultValue` is returned.

Three rule kinds are supported:

- **Condition** — every `Condition` must match (AND). Operators: `eq`, `neq`, `in`, `notIn`, `gt`, `gte`, `lt`, `lte`, `contains`, `startsWith`, `endsWith`. Type-incompatible comparisons (string vs. int) cleanly return false.
- **Rollout** — bucketing key is `"<flagKey>:<userID>"`, hashed with SHA-256. The first 8 bytes of the digest are interpreted as a big-endian `UInt64` and reduced modulo 100. The same `(flagKey, userID)` pair always lands in the same bucket, so users don't flicker between variants on relaunch.
- **Split** — same hash, reduced modulo the sum of weights. The bucket is then walked through the variant array to pick a winner. Only meaningful for string flags.

Both `rollout` and `split` require a `userID`. Without one they fall through.

## SwiftUI bridge

``HoistObservable`` is a `@MainActor @Observable` singleton with one mutable property — a monotonically-increasing `version` counter. It has no flag data of its own. The ``FeatureFlag`` property wrapper reads `version` inside the SwiftUI body to establish an Observation dependency, so any tick (from `configure`, `update`, `reset`, or an override mutation) re-renders every consuming view.

This separation keeps the lock-protected `Storage` off the main actor — flag reads remain synchronous from any thread, and the Observation overhead is opt-in (only views that use `@FeatureFlag` subscribe).

## Persistence

Overrides are persisted via ``OverrideStore`` to the dedicated `UserDefaults` suite `com.hoist.overrides`. The whole map is serialised as JSON under one key, so saves are atomic. Persistence is synchronous and unconditional — it works in DEBUG and release alike. If you don't want overrides surviving in production, gate the *UI* with `#if DEBUG`, not the API.

## What Hoist deliberately doesn't do

- No background polling or push transport.
- No analytics SDK, no event pipeline, no ID assignment.
- No DI container; the public API is namespaced static methods on the `Hoist` enum.
- No remote evaluation — all rules are evaluated client-side from a local document.

These are conscious omissions. They keep the dependency graph trivial and the audit surface small. Items in the roadmap (remote sync, layered sources, exposure hooks) will preserve the same constraints.
