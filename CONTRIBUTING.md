# Contributing to Hoist

Thanks for your interest in improving Hoist! This document explains how to file
issues, propose changes, and get a pull request merged.

## Filing issues

Before opening a new issue, please:

1. **Search existing issues** to avoid duplicates.
2. **Include reproductions** for bugs: a minimal `flags.json`, the relevant
   `UserContext`, the call site, the actual vs. expected behaviour, and your
   Swift / Xcode / OS versions.
3. For security vulnerabilities, **do not open a public issue**. Use GitHub's
   private vulnerability reporting under the repository's **Security** tab.

## Local development

```bash
git clone https://github.com/GRimAce11/Hoist.git
cd Hoist
swift build
swift test
```

You'll need Swift 6.0 or newer (Xcode 16+).

## Pull requests

We're happy to accept contributions. To make merging smooth:

1. **Open an issue first** for non-trivial changes so we can agree on the
   approach before you invest time.
2. **Branch from `main`** and use a descriptive branch name
   (e.g. `fix/rollout-edge-case`, `feat/remote-polling`).
3. **Add tests** for new behaviour. Hoist's test suite is fast and
   deterministic; let's keep it that way.
4. **Keep PRs focused.** One conceptual change per PR.
5. **Run `swift test` locally** and make sure CI is green before requesting review.
6. **Update `CHANGELOG.md`** under the `[Unreleased]` heading for any user-facing change.
7. **Document new public APIs** with `///` doc comments. DocC consumes them.

### Coding conventions

- **Swift 6 strict concurrency.** No new `@unchecked Sendable` without a clear
  comment justifying why it's safe.
- **Pure functions where possible.** The evaluator is intentionally side-effect
  free — keep it that way.
- **No new third-party dependencies.** Hoist's value proposition is
  zero-deps. Reach for the standard library, Foundation, CryptoKit,
  Observation, or SwiftUI before adding anything to `Package.swift`.
- **Public API stability.** Any breaking change to a public type, method, or
  property must be called out in the PR description and reflected as a
  semver-major bump.

### Commit messages

Short imperative subject line (≤72 chars), followed by a blank line and an
optional body explaining the *why* of the change. Reference issues with
`Fixes #123` or `Refs #123`.

## What we'd love help with

Good first PRs:

- Bug fixes with a failing test attached.
- Documentation improvements — examples, DocC articles, typo fixes.
- New tests for edge cases.

Bigger conversations welcome (open an issue first):

- Remote sync transport (polling, SSE, WebSocket).
- Analytics exposure hooks.
- A reference server for self-hosting.
- DocC tutorials for common adoption flows.

Thanks for helping make Hoist better. 🛠️
