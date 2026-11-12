import AVFoundation
import CryptoKit
import Foundation

public enum WebMediaNativeAssetOptionsError: Error, LocalizedError, Equatable {
    case unsupportedRequiredHeaders([String])
    case ambiguousUserAgent
    case unsupportedUserAgent

    public var errorDescription: String? {
        switch self {
        case .unsupportedRequiredHeaders:
            return "This media requires playback or download options that aren’t supported."
        case .ambiguousUserAgent:
            return "This media’s playback information is inconsistent. Try reopening its webpage."
        case .unsupportedUserAgent:
            return "This media needs a newer operating system to play or download."
        }
    }
}

/// Shared by background HLS and the owning native player. Local artifacts need
/// no remote credentials; remote assets use only documented AVFoundation keys.
public enum WebMediaNativeAssetOptions {
    public static func options(for media: ResolvedWebMedia, httpCookies: [HTTPCookie]? = nil) throws -> [String: Any]? {
        guard !media.url.isFileURL else { return nil }
        return try WebMediaHLSCookieContext.assetOptions(headers: media.requestHeaders,
            cookieContext: httpCookies.map(WebMediaHLSCookieContext.init),
            nativeOptionalRequestHeaders: media.nativeOptionalRequestHeaders)
    }
}

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
        cookieContext: WebMediaHLSCookieContext?,
        nativeOptionalRequestHeaders: [String: String] = [:]
    ) throws -> [String: Any]? {
        let optional = WebMediaRequestContext.matchingNativeOptionalHeaders(nativeOptionalRequestHeaders, in: headers)
        var required = headers.filter { optional[$0.key] != $0.value }
        var options: [String: Any] = [:]
        if let cookieContext {
            // Scoped objects replace raw Cookie, including an explicitly empty
            // captured store; a string alone cannot recover destination scope.
            required = required.filter { $0.key.caseInsensitiveCompare("Cookie") != .orderedSame }
            options[AVURLAssetHTTPCookiesKey] = cookieContext.cookies
        }
        let userAgents = required.filter { $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame }
        guard userAgents.count <= 1 else { throw WebMediaNativeAssetOptionsError.ambiguousUserAgent }
        required = required.filter { $0.key.caseInsensitiveCompare("User-Agent") != .orderedSame }
        guard required.isEmpty else {
            throw WebMediaNativeAssetOptionsError.unsupportedRequiredHeaders(required.keys.sorted())
        }
        if let userAgent = userAgents.first?.value {
            if #available(iOS 16.0, macOS 13.0, macCatalyst 16.0, *) {
                options[AVURLAssetHTTPUserAgentKey] = userAgent
            } else {
                throw WebMediaNativeAssetOptionsError.unsupportedUserAgent
            }
        }
        return options.isEmpty ? nil : options
    }
}
