import Foundation
import os
@testable import Hoist

/// A `URLProtocol` subclass used by integration tests to intercept the
/// requests Hoist makes via `FlagSource.url(...)` and return canned
/// responses. Register URL → handler pairs with `register(_:handler:)`,
/// then attach the protocol to a `URLSession` via `StubbedHoistSession`.
///
/// Handlers receive the captured `URLRequest` (so tests can assert on
/// request headers like `Authorization` or `If-None-Match`) and return the
/// response code, headers, and body to send back.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (statusCode: Int, headers: [String: String], body: Data?)

    private static let handlers = OSAllocatedUnfairLock<[String: Handler]>(initialState: [:])

    static func register(_ urlString: String, handler: @escaping Handler) {
        handlers.withLock { $0[urlString] = handler }
    }

    static func clearAll() {
        handlers.withLock { $0.removeAll() }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return handlers.withLock { $0[url.absoluteString] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let handler = Self.handlers.withLock({ $0[url.absoluteString] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let result = handler(request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: result.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: result.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body = result.body {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Convenience: install a `URLSession` wired to `StubURLProtocol`, swap it
/// into `Hoist.urlSession`, and return a teardown closure that restores
/// the original session and clears registered handlers.
///
/// ```swift
/// let restore = StubbedHoistSession.install()
/// defer { restore() }
/// StubURLProtocol.register("https://flags.test/x.json") { _ in (200, [:], Data()) }
/// ```
enum StubbedHoistSession {
    static func install() -> @Sendable () -> Void {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let original = Hoist.urlSession
        Hoist.urlSession = session
        return {
            Hoist.urlSession = original
            session.invalidateAndCancel()
            StubURLProtocol.clearAll()
        }
    }
}
