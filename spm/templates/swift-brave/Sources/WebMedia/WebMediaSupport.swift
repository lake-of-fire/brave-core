import Foundation
import WebKit
import SwiftUIWebView

public struct WebMediaScriptSet: Sendable {
    public let webMediaScripts: WebMediaBuiltScriptSet
    public let userScripts: [WebViewUserScript]

    public var messageHandlerName: String {
        webMediaScripts.configuration.messageHandlerName
    }

    public var securityToken: String {
        webMediaScripts.configuration.securityToken
    }

    public var processDocumentLoadJavaScript: String {
        webMediaScripts.processDocumentLoadJavaScript
    }
}

public enum WebMediaScripts {
    public static func make(
        messageHandlerName: String,
        allowedDomains: Set<String> = [],
        configuration: WebMediaScriptConfiguration? = nil
    ) throws -> WebMediaScriptSet {
        let configuration = configuration ?? WebMediaScriptConfiguration(messageHandlerName: messageHandlerName)
        let webMediaScripts = try WebMediaScriptEngine.makeScriptSet(configuration: configuration)
        let userScripts = [
            WebViewUserScript(
                source: webMediaScripts.firefoxShimSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                allowedDomains: allowedDomains
            ),
            WebViewUserScript(
                source: webMediaScripts.mediaSourceOverrideSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                allowedDomains: allowedDomains
            ),
            WebViewUserScript(
                source: webMediaScripts.detectorSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                allowedDomains: allowedDomains
            ),
        ]

        return WebMediaScriptSet(
            webMediaScripts: webMediaScripts,
            userScripts: userScripts
        )
    }
}

public enum WebMediaMessageDecoder {
    public static func decode(
        message: WebViewMessage,
        scriptSet: WebMediaScriptSet
    ) -> WebMediaScriptMessage? {
        decode(body: message.body, scriptSet: scriptSet)
    }

    public static func decode(
        body: Any,
        scriptSet: WebMediaScriptSet
    ) -> WebMediaScriptMessage? {
        WebMediaScriptMessageDecoder.decode(
            body: body,
            expectingSecurityToken: scriptSet.securityToken
        )
    }
}

public enum WebMediaCandidateSelector {
    public static func preferredCandidate(
        from candidates: [WebMediaInfo],
        preferringAudio: Bool = true
    ) -> WebMediaInfo? {
        collapsedCandidates(from: candidates).max { lhs, rhs in
            compare(lhs, rhs, preferringAudio: preferringAudio) == .orderedAscending
        }
    }

    private static func collapsedCandidates(from candidates: [WebMediaInfo]) -> [WebMediaInfo] {
        Dictionary(grouping: candidates) { candidate in
            candidate.tagId.isEmpty ? UUID().uuidString : candidate.tagId
        }
        .values
        .compactMap { group in
            group.max { lhs, rhs in
                compareRefreshedCandidates(lhs, rhs) == .orderedAscending
            }
        }
    }

    private static func compare(
        _ lhs: WebMediaInfo,
        _ rhs: WebMediaInfo,
        preferringAudio: Bool
    ) -> ComparisonResult {
        let lhsScore = score(lhs, preferringAudio: preferringAudio)
        let rhsScore = score(rhs, preferringAudio: preferringAudio)
        if lhsScore != rhsScore {
            return lhsScore < rhsScore ? .orderedAscending : .orderedDescending
        }
        if lhs.playbackKind != rhs.playbackKind {
            return playbackPriority(lhs.playbackKind, preferringAudio: preferringAudio)
                < playbackPriority(rhs.playbackKind, preferringAudio: preferringAudio)
                ? .orderedAscending
                : .orderedDescending
        }
        if lhs.duration != rhs.duration {
            return lhs.duration < rhs.duration ? .orderedAscending : .orderedDescending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
    }

    private static func score(_ candidate: WebMediaInfo, preferringAudio: Bool) -> Int {
        var score = 0
        if !candidate.isInvisible {
            score += 8
        }
        if !candidate.isLikelyAdvertisement {
            score += 10
        }
        if candidate.isHTTPSource {
            score += 8
        } else if !candidate.isBlobSource && !candidate.isDataSource {
            score += 4
        }
        if candidate.detected {
            score += 4
        }
        if candidate.duration > 0 {
            score += 2
        }
        if candidate.containerKind == .hls {
            score += 1
        }
        if preferringAudio {
            switch candidate.playbackKind {
            case .audioOnly:
                score += 6
            case .video:
                score += 3
            case .unknown:
                break
            }
        } else if candidate.playbackKind == .video {
            score += 6
        }
        return score
    }

    private static func compareRefreshedCandidates(
        _ lhs: WebMediaInfo,
        _ rhs: WebMediaInfo
    ) -> ComparisonResult {
        let lhsScore = refreshScore(lhs)
        let rhsScore = refreshScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore < rhsScore ? .orderedAscending : .orderedDescending
        }
        if lhs.duration != rhs.duration {
            return lhs.duration < rhs.duration ? .orderedAscending : .orderedDescending
        }
        return lhs.src.localizedCaseInsensitiveCompare(rhs.src)
    }

    private static func refreshScore(_ candidate: WebMediaInfo) -> Int {
        var score = 0
        if candidate.isHTTPSource {
            score += 8
        }
        if !candidate.isBlobSource && !candidate.isDataSource {
            score += 4
        }
        if candidate.normalizedMimeType != nil {
            score += 2
        }
        if candidate.duration > 0 {
            score += 1
        }
        return score
    }

    private static func playbackPriority(
        _ playbackKind: WebMediaPlaybackKind,
        preferringAudio: Bool
    ) -> Int {
        if preferringAudio {
            switch playbackKind {
            case .audioOnly:
                return 3
            case .video:
                return 2
            case .unknown:
                return 1
            }
        }

        switch playbackKind {
        case .video:
            return 3
        case .audioOnly:
            return 2
        case .unknown:
            return 1
        }
    }
}

public enum WebMediaRequestContextBuilder {
    public static func make(
        userAgent: String? = nil,
        referer: URL? = nil,
        cookies: [HTTPCookie] = []
    ) -> WebMediaRequestContext {
        WebMediaRequestContext(
            userAgent: userAgent,
            referer: referer,
            cookieHeader: cookieHeader(for: cookies)
        )
    }

    @MainActor
    public static func make(
        webView: WKWebView,
        referer: URL? = nil
    ) async -> WebMediaRequestContext {
        let cookies = await cookies(from: webView.configuration.websiteDataStore.httpCookieStore)
        let userAgent = await resolveUserAgent(for: webView)
        return make(
            userAgent: userAgent,
            referer: referer ?? webView.url,
            cookies: cookies
        )
    }

    public static func cookieHeader(for cookies: [HTTPCookie]) -> String? {
        guard !cookies.isEmpty else {
            return nil
        }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    @MainActor
    private static func resolveUserAgent(for webView: WKWebView) async -> String? {
        if let customUserAgent = webView.customUserAgent,
           !customUserAgent.isEmpty {
            return customUserAgent
        }

        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("navigator.userAgent") { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }

    @MainActor
    private static func cookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}
