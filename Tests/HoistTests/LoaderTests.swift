import Testing
import Foundation
@testable import Hoist

@Suite("Loader")
struct LoaderTests {

    @Test func decodesAllRuleKinds() throws {
        let json = """
        {
          "flags": {
            "a_bool": {
              "type": "bool",
              "default": false,
              "rules": [
                { "if": { "country": "US" }, "value": true },
                { "rollout": 25, "value": true }
              ]
            },
            "an_int": {
              "type": "int",
              "default": 10,
              "rules": [
                { "if": { "plan": { "in": ["pro", "team"] } }, "value": 100 }
              ]
            },
            "a_string": {
              "type": "string",
              "default": "grid",
              "rules": [
                { "split": { "grid": 50, "list": 50 } }
              ]
            }
          }
        }
        """
        let doc = try JSONDecoder().decode(FlagDocument.self, from: Data(json.utf8))

        let bool = try #require(doc.flags["a_bool"])
        #expect(bool.type == .bool)
        #expect(bool.defaultValue == .bool(false))
        #expect(bool.rules.count == 2)

        let int = try #require(doc.flags["an_int"])
        #expect(int.type == .int)
        #expect(int.defaultValue == .int(10))

        let string = try #require(doc.flags["a_string"])
        #expect(string.type == .string)
        #expect(string.rules.count == 1)
        if case .split(let variants) = string.rules[0] {
            #expect(variants.count == 2)
            #expect(Set(variants.map(\.value)) == ["grid", "list"])
        } else {
            Issue.record("expected split rule, got \(string.rules[0])")
        }
    }

    @Test func decodesOperatorSugarAsEquality() throws {
        let json = """
        {
          "flags": {
            "x": {
              "type": "bool",
              "default": false,
              "rules": [{ "if": { "country": "US" }, "value": true }]
            }
          }
        }
        """
        let doc = try JSONDecoder().decode(FlagDocument.self, from: Data(json.utf8))
        let flag = try #require(doc.flags["x"])
        if case .condition(let conditions, _) = flag.rules[0] {
            #expect(conditions.count == 1)
            if case .eq(let value) = conditions[0].operator {
                #expect(value == .string("US"))
            } else {
                Issue.record("expected .eq operator")
            }
        } else {
            Issue.record("expected condition rule")
        }
    }

    @Test func rejectsRolloutOutOfRange() {
        let json = """
        {
          "flags": {
            "x": {
              "type": "bool",
              "default": false,
              "rules": [{ "rollout": 150, "value": true }]
            }
          }
        }
        """
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(FlagDocument.self, from: Data(json.utf8))
        }
    }

    @Test func rejectsRuleWithoutKnownKey() {
        let json = """
        {
          "flags": {
            "x": {
              "type": "bool",
              "default": false,
              "rules": [{ "value": true }]
            }
          }
        }
        """
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(FlagDocument.self, from: Data(json.utf8))
        }
    }

    @Test func loadsBundledResource() async throws {
        let source = FlagSource.bundled(filename: "sample-flags.json", bundle: .module)
        let document = try await source.load()
        #expect(document.flags.count == 8)
        #expect(document.flags["bool_country_us"]?.rules.count == 1)
    }

    @Test func bundledMissingFileThrows() async {
        let source = FlagSource.bundled(filename: "does-not-exist.json", bundle: .module)
        await #expect(throws: FlagSourceError.self) {
            try await source.load()
        }
    }

    // MARK: - Schema versioning

    @Test func documentWithoutSchemaVersionLoadsAsV1() async throws {
        let json = """
        {
          "flags": {
            "x": { "type": "bool", "default": false }
          }
        }
        """
        let doc = try await FlagSource.data(Data(json.utf8)).load()
        #expect(doc.resolvedSchemaVersion == 1)
        #expect(doc.flags["x"]?.defaultValue == .bool(false))
    }

    @Test func documentWithSupportedSchemaVersionLoads() async throws {
        let json = """
        {
          "schemaVersion": 1,
          "flags": {
            "x": { "type": "bool", "default": true }
          }
        }
        """
        let doc = try await FlagSource.data(Data(json.utf8)).load()
        #expect(doc.schemaVersion == 1)
        #expect(doc.flags["x"]?.defaultValue == .bool(true))
    }

    @Test func documentWithUnsupportedSchemaVersionThrows() async {
        let json = """
        {
          "schemaVersion": 99,
          "flags": {
            "x": { "type": "bool", "default": false }
          }
        }
        """
        await #expect {
            try await FlagSource.data(Data(json.utf8)).load()
        } throws: { error in
            guard case FlagSourceError.unsupportedSchemaVersion(let found, _) = error else {
                return false
            }
            return found == 99
        }
    }
}
