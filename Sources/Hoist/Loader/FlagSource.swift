import Foundation

/// Where Hoist loads its flag configuration from.
///
/// - `bundled`: a JSON file shipped inside the app bundle.
/// - `data`: raw JSON bytes (useful for testing or pre-loaded configs).
/// - `url`: a remote JSON endpoint, fetched once via `URLSession`. Hoist does
///   not poll — the document is loaded a single time per `configure(...)` call.
///   For background refresh, schedule your own `Hoist.configure(...)` calls.
/// - `layered`: an ordered list of fallback sources. Layers load sequentially;
///   individual layer failures are tolerated, and the resulting documents are
///   merged per-flag-key with **later layers overriding earlier ones**. The
///   common shape is `.layered([.bundled("defaults.json"), .url(remote)])`:
///   bundled defaults are the floor, the remote document fills in or
///   overrides per key. If every layer fails, the error from the last
///   attempted layer is rethrown.
public enum FlagSource: @unchecked Sendable {
    case bundled(filename: String, bundle: Bundle = .main)
    case data(Data)
    case url(URL)
    indirect case layered([FlagSource])
}

/// Errors that can be thrown while loading a flag configuration.
public enum FlagSourceError: Error, LocalizedError, Equatable {
    case fileNotFound(filename: String)
    case decoding(message: String)
    case network(message: String)
    case unsupportedSchemaVersion(found: Int, supported: [Int])

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let filename):
            return "Hoist: configuration file '\(filename)' was not found in the bundle."
        case .decoding(let message):
            return "Hoist: failed to decode flag configuration — \(message)"
        case .network(let message):
            return "Hoist: failed to fetch remote flag configuration — \(message)"
        case .unsupportedSchemaVersion(let found, let supported):
            let supportedList = supported.sorted().map(String.init).joined(separator: ", ")
            return "Hoist: flag document declares schemaVersion \(found), but this build of Hoist only supports [\(supportedList)]. Upgrade Hoist or downgrade the document."
        }
    }
}

extension FlagSource {
    /// Loads and parses the flag document.
    func load() async throws -> FlagDocument {
        switch self {
        case .bundled(let filename, let bundle):
            return try Self.loadBundled(filename: filename, bundle: bundle)
        case .data(let data):
            return try Self.decode(data)
        case .url(let url):
            return try await Self.loadRemote(url: url)
        case .layered(let layers):
            return try await Self.loadLayered(layers: layers)
        }
    }

    private static func loadLayered(layers: [FlagSource]) async throws -> FlagDocument {
        guard !layers.isEmpty else {
            throw FlagSourceError.decoding(message: "layered source requires at least one layer")
        }
        var merged: [String: Flag] = [:]
        var schemaVersion: Int? = nil
        var lastError: Error? = nil
        var anySucceeded = false
        for layer in layers {
            do {
                let document = try await layer.load()
                anySucceeded = true
                schemaVersion = document.schemaVersion ?? schemaVersion
                for (key, flag) in document.flags {
                    merged[key] = flag
                }
            } catch {
                lastError = error
            }
        }
        if !anySucceeded, let error = lastError {
            throw error
        }
        return FlagDocument(schemaVersion: schemaVersion, flags: merged)
    }

    private static func loadBundled(filename: String, bundle: Bundle) throws -> FlagDocument {
        let (name, ext) = splitExtension(filename)
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw FlagSourceError.fileNotFound(filename: filename)
        }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    private static func loadRemote(url: URL) async throws -> FlagDocument {
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw FlagSourceError.network(message: error.localizedDescription)
        }
        return try decode(data)
    }

    private static func decode(_ data: Data) throws -> FlagDocument {
        let document: FlagDocument
        do {
            document = try JSONDecoder().decode(FlagDocument.self, from: data)
        } catch {
            throw FlagSourceError.decoding(message: String(describing: error))
        }
        let version = document.resolvedSchemaVersion
        guard Hoist.supportedSchemaVersions.contains(version) else {
            throw FlagSourceError.unsupportedSchemaVersion(
                found: version,
                supported: Array(Hoist.supportedSchemaVersions)
            )
        }
        return document
    }

    private static func splitExtension(_ filename: String) -> (name: String, ext: String) {
        if let dot = filename.lastIndex(of: ".") {
            let name = String(filename[..<dot])
            let ext = String(filename[filename.index(after: dot)...])
            return (name, ext)
        }
        return (filename, "json")
    }
}
