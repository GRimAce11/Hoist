import Foundation

/// Where Hoist loads its flag configuration from.
///
/// - `bundled`: a JSON file shipped inside the app bundle.
/// - `data`: raw JSON bytes (useful for testing or pre-loaded configs).
/// - `url`: a remote JSON endpoint, fetched once via `URLSession`.
public enum FlagSource: @unchecked Sendable {
    case bundled(filename: String, bundle: Bundle = .main)
    case data(Data)
    case url(URL)
}

/// Errors that can be thrown while loading a flag configuration.
public enum FlagSourceError: Error, LocalizedError, Equatable {
    case fileNotFound(filename: String)
    case decoding(message: String)
    case network(message: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let filename):
            return "Hoist: configuration file '\(filename)' was not found in the bundle."
        case .decoding(let message):
            return "Hoist: failed to decode flag configuration — \(message)"
        case .network(let message):
            return "Hoist: failed to fetch remote flag configuration — \(message)"
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
        }
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
        do {
            return try JSONDecoder().decode(FlagDocument.self, from: data)
        } catch {
            throw FlagSourceError.decoding(message: String(describing: error))
        }
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
