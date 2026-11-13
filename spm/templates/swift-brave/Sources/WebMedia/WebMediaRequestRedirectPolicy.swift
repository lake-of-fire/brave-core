import Foundation

/// Bounds HTTP redirect chains and prevents credentials supplied for one
/// resource origin from following a redirect to an unrelated host.
final class WebMediaRequestRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let originalURL: URL
    private let maximumRedirects: Int
    private let lock = NSLock()
    private var redirectCount = 0

    init(url: URL, maximumRedirects: Int = 8) {
        originalURL = url
        self.maximumRedirects = maximumRedirects
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        lock.lock()
        redirectCount += 1
        let allowed = redirectCount <= maximumRedirects
        lock.unlock()
        guard allowed, let target = request.url,
              ["http", "https"].contains(target.scheme?.lowercased() ?? ""),
              target.user == nil, target.password == nil,
              !(originalURL.scheme?.lowercased() == "https" && target.scheme?.lowercased() != "https") else {
            completionHandler(nil)
            return
        }
        var redirected = request
        if Self.origin(response.url ?? originalURL) != Self.origin(target) {
            // Foundation strips standard Authorization in many cases. Custom
            // credential headers need the same origin boundary explicitly.
            let permitted: Set<String> = ["accept", "accept-language", "accept-encoding", "user-agent",
                                          "range", "if-range", "cache-control", "pragma", "referer"]
            for name in redirected.allHTTPHeaderFields?.keys ?? Dictionary<String, String>().keys {
                if !permitted.contains(name.lowercased()) { redirected.setValue(nil, forHTTPHeaderField: name) }
            }
            if let referer = redirected.value(forHTTPHeaderField: "Referer"), let url = URL(string: referer) {
                redirected.setValue(Self.origin(url).map { $0 + "/" }, forHTTPHeaderField: "Referer")
            }
        }
        completionHandler(redirected)
    }

    private static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }
}
