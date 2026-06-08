import Foundation

#if DEBUG
/// Debug-only sentinel that fires `assertionFailure` whenever the app makes an
/// HTTP request through `URLSession.shared`. The privacy promise is that the
/// only outbound traffic comes from `WebFetchService` (which uses its own
/// `URLSession(configuration: .ephemeral)` instance). If anything ever leaks
/// through the shared session — analytics SDKs, image AsyncImage to remote
/// URLs, errant code — this catches it in development.
enum NetworkGuard {
    /// Call once from `EmberApp.init` (DEBUG-only).
    static func arm() {
        URLProtocol.registerClass(BlockingProtocol.self)
    }

    private final class BlockingProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            guard let scheme = request.url?.scheme?.lowercased() else { return false }
            guard scheme == "http" || scheme == "https" else { return false }
            // Allow WebFetchService's intentional outbound fetches through.
            if request.value(forHTTPHeaderField: "X-Ember-Fetch") == "1" { return false }
            return true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url?.absoluteString ?? "<unknown>"
            assertionFailure("""
                [NetworkGuard] Unexpected outbound request via URLSession.shared: \(url)
                All web requests must go through WebFetchService (.ephemeral session).
                """)
            client?.urlProtocol(
                self,
                didFailWithError: NSError(domain: "NetworkGuard", code: -1)
            )
        }

        override func stopLoading() {}
    }
}
#endif
