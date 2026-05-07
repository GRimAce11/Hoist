// Reference snippet — not compiled by the package.
//
// Recommended pattern for testing code that reads Hoist flags:
//
//   1. `await Hoist.reset()` — clears flags, context, and overrides.
//   2. `try await Hoist.configure(source: .data(...), context: ...)`
//      — load a tiny inline JSON document.
//   3. Assert on `Hoist.bool/int/string/double` or your code under test.
//
// Hoist holds a single global state. If you run tests in parallel across
// multiple suites that touch `Hoist.configure(...)`, group them under one
// `.serialized` parent suite to prevent races.

import Foundation
import Testing
@testable import MyApp
import Hoist

@Suite("Checkout flow", .serialized)
struct CheckoutFlowTests {

    @Test func newCheckoutForUSUsers() async throws {
        let json = #"""
        {
          "flags": {
            "new_checkout": {
              "type": "bool",
              "default": false,
              "rules": [{ "if": { "country": "US" }, "value": true }]
            }
          }
        }
        """#

        await Hoist.reset()
        try await Hoist.configure(
            source: .data(Data(json.utf8)),
            context: UserContext(userID: "test_user", attributes: ["country": .string("US")])
        )

        #expect(Hoist.bool("new_checkout") == true)
    }

    @Test func legacyCheckoutForOtherCountries() async throws {
        let json = #"""
        {
          "flags": {
            "new_checkout": {
              "type": "bool",
              "default": false,
              "rules": [{ "if": { "country": "US" }, "value": true }]
            }
          }
        }
        """#

        await Hoist.reset()
        try await Hoist.configure(
            source: .data(Data(json.utf8)),
            context: UserContext(userID: "test_user", attributes: ["country": .string("DE")])
        )

        #expect(Hoist.bool("new_checkout") == false)
    }

    @Test func overridePinsValueRegardlessOfRules() async throws {
        await Hoist.reset()
        try await Hoist.configure(
            source: .data(Data(#"{ "flags": { "new_checkout": { "type": "bool", "default": false } } }"#.utf8)),
            context: .anonymous
        )

        // Force the flag ON for this test.
        Hoist.override("new_checkout", with: true)
        #expect(Hoist.bool("new_checkout") == true)
    }
}
