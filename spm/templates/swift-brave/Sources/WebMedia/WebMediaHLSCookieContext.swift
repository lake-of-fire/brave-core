import AVFoundation
import CryptoKit
import Foundation

/// Immutable cookies retain their domain/path/Secure semantics in AVFoundation.
/// Only a digest contributes to the durable transfer identity; cookie values are
/// never added to the coordinator's journal or a resource-wide Cookie header.
struct WebMediaHLSCookieContext: @unchecked Sendable {
    let cookies: [HTTPCookie]

    init(_ cookies: [HTTPCookie]) {
        self.cookies = cookies
    }

    func requestKey(base: String) throws -> String {
        let identities = cookies.map { cookie in
            [cookie.name, cookie.value, cookie.domain, cookie.path,
             cookie.isSecure ? "secure" : "nonsecure",
             cookie.expiresDate.map { String($0.timeIntervalSince1970) } ?? "session",
             String(cookie.version),
             cookie.portList?.map { String($0.intValue) }.joined(separator: ",") ?? ""]
        }
        // Preserve ordering: two equal names can apply at different paths, and
        // their precedence must not collapse to one resumable representation.
        let data = try JSONEncoder().encode(identities)
        return SHA256.hash(data: Data(base.utf8) + Data([0x1f]) + data)
            .map { String(format: "%02x", $0) }.joined()
    }

    static func assetOptions(
        headers: [String: String],
        cookieContext: WebMediaHLSCookieContext?
    ) -> [String: Any]? {
        var headers = headers
        var options: [String: Any] = [:]
        if let cookieContext {
            // A raw header would bypass the cookie objects' destination scope.
            headers = headers.filter { $0.key.caseInsensitiveCompare("Cookie") != .orderedSame }
            options[AVURLAssetHTTPCookiesKey] = cookieContext.cookies
        }
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        return options.isEmpty ? nil : options
    }
}
