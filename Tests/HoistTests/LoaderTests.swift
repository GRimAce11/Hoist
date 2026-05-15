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
        if case .split(let conditions, let variants) = string.rules[0] {
            #expect(conditions.isEmpty)
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

    @Test func decodesIfCombinedWithRollout() throws {
        let json = """
        {
          "flags": {
            "x": {
              "type": "bool",
              "default": false,
              "rules": [
                { "if": { "country": { "in": ["US", "CA"] } }, "rollout": 25, "value": true }
              ]
            }
          }
        }
        """
        let doc = try JSONDecoder().decode(FlagDocument.self, from: Data(json.utf8))
        let flag = try #require(doc.flags["x"])
        guard case .rollout(let conditions, let percentage, let value) = flag.rules[0] else {
            Issue.record("expected rollout rule, got \(flag.rules[0])")
            return
        }
        #expect(percentage == 25)
        #expect(value == .bool(true))
        #expect(conditions.count == 1)
        #expect(conditions[0].attribute == "country")
        if case .in(let values) = conditions[0].operator {
            #expect(values == [.string("US"), .string("CA")])
        } else {
            Issue.record("expected .in operator")
        }
    }

    @Test func decodesIfCombinedWithSplit() throws {
        let json = """
        {
          "flags": {
            "x": {
              "type": "string",
              "default": "grid",
              "rules": [
                { "if": { "plan": "pro" }, "split": { "a": 50, "b": 50 } }
              ]
            }
          }
        }
        """
        let doc = try JSONDecoder().decode(FlagDocument.self, from: Data(json.utf8))
        let flag = try #require(doc.flags["x"])
        guard case .split(let conditions, let variants) = flag.rules[0] else {
            Issue.record("expected split rule, got \(flag.rules[0])")
            return
        }
        #expect(conditions.count == 1)
        #expect(conditions[0].attribute == "plan")
        #expect(variants.count == 2)
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

    // MARK: - Layered sources

    private static let baseLayer = """
    {
      "schemaVersion": 1,
      "flags": {
        "a": { "type": "bool", "default": false },
        "b": { "type": "int",  "default": 10 }
      }
    }
    """

    private static let overrideLayer = """
    {
      "schemaVersion": 1,
      "flags": {
        "b": { "type": "int",    "default": 999 },
        "c": { "type": "string", "default": "hello" }
      }
    }
    """

    @Test func layeredMergesWithLaterWinning() async throws {
        let source = FlagSource.layered([
            .data(Data(Self.baseLayer.utf8)),
            .data(Data(Self.overrideLayer.utf8)),
        ])
        let doc = try await source.load()

        #expect(doc.flags["a"]?.defaultValue == .bool(false))   // only in base
        #expect(doc.flags["b"]?.defaultValue == .int(999))      // override wins
        #expect(doc.flags["c"]?.defaultValue == .string("hello")) // only in override
        #expect(doc.flags.count == 3)
    }

    @Test func layeredTolerantOfFailingLayer() async throws {
        let source = FlagSource.layered([
            .data(Data(Self.baseLayer.utf8)),
            .bundled(filename: "missing.json", bundle: .module), // this fails
        ])
        let doc = try await source.load()

        // Base survives even though the URL/bundled layer failed.
        #expect(doc.flags["a"]?.defaultValue == .bool(false))
        #expect(doc.flags["b"]?.defaultValue == .int(10))
    }

    @Test func layeredThrowsLastErrorWhenAllFail() async {
        let source = FlagSource.layered([
            .bundled(filename: "first-missing.json", bundle: .module),
            .bundled(filename: "second-missing.json", bundle: .module),
        ])
        await #expect {
            try await source.load()
        } throws: { error in
            guard case FlagSourceError.fileNotFound(let filename) = error else {
                return false
            }
            return filename == "second-missing.json"
        }
    }

    @Test func layeredEmptyThrows() async {
        let source = FlagSource.layered([])
        await #expect(throws: FlagSourceError.self) {
            try await source.load()
        }
    }

    // MARK: - Poll interval scanning

    @Test func sourceWithoutPollIntervalReportsNoPolling() {
        let url = URL(string: "https://example.com/flags.json")!
        #expect(FlagSource.bundled(filename: "x.json").shortestPollInterval == nil)
        #expect(FlagSource.data(Data()).shortestPollInterval == nil)
        #expect(FlagSource.url(url).shortestPollInterval == nil)
    }

    @Test func urlSourceWithPollIntervalReportsInterval() {
        let url = URL(string: "https://example.com/flags.json")!
        #expect(FlagSource.url(url, pollInterval: 60).shortestPollInterval == 60)
    }

    @Test func layeredPicksShortestPollInterval() {
        let a = URL(string: "https://example.com/a")!
        let b = URL(string: "https://example.com/b")!
        let source = FlagSource.layered([
            .bundled(filename: "x.json"),
            .url(a, pollInterval: 120),
            .url(b, pollInterval: 30),
        ])
        #expect(source.shortestPollInterval == 30)
    }

    @Test func layeredWithoutAnyPollingReportsNil() {
        let a = URL(string: "https://example.com/a")!
        let source = FlagSource.layered([
            .bundled(filename: "x.json"),
            .url(a),
        ])
        #expect(source.shortestPollInterval == nil)
    }
}
