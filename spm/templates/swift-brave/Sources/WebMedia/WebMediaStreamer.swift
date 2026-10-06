import Foundation

public protocol WebMediaLoaderFactory {
    func makeWebLoader() -> any WebMediaLoader
}

public protocol WebMediaLoader: AnyObject {
    func load(url: URL) async -> WebMediaInfo?
    func stop()
}

public struct WebMediaRequestContext: Hashable, Sendable {
    public let headers: [String: String]

    public init(
        headers: [String: String] = [:],
        userAgent: String? = nil,
        referer: URL? = nil,
        cookieHeader: String? = nil
    ) {
        var headers = headers
        if let userAgent {
            headers["User-Agent"] = userAgent
        }
        if let referer {
            headers["Referer"] = referer.absoluteString
        }
        if let cookieHeader {
            headers["Cookie"] = cookieHeader
        }
        self.headers = headers
    }
}

public enum WebMediaResolutionMethod: String, Hashable, Codable, Sendable {
    case direct
    case fallback
}

public struct ResolvedWebMedia: Hashable, Sendable {
    public let mediaInfo: WebMediaInfo
    public let url: URL
    public let mimeType: String?
    public let requestHeaders: [String: String]
    public let resolutionMethod: WebMediaResolutionMethod

    public init(
        mediaInfo: WebMediaInfo,
        url: URL,
        mimeType: String?,
        requestHeaders: [String: String] = [:],
        resolutionMethod: WebMediaResolutionMethod
    ) {
        self.mediaInfo = mediaInfo
        self.url = url
        self.mimeType = mimeType
        self.requestHeaders = requestHeaders
        self.resolutionMethod = resolutionMethod
    }
}

public final class WebMediaStreamer: @unchecked Sendable {
    public enum PlaybackError: Error, Equatable {
        case unsupportedSource
        case couldNotDeterminePlayableMedia
        case fallbackUnavailable
        case fallbackDidNotResolvePlayableMedia
    }

    private let urlSession: URLSession
    private let webLoaderFactory: (any WebMediaLoaderFactory)?

    public init(
        urlSession: URLSession = .shared,
        webLoaderFactory: (any WebMediaLoaderFactory)? = nil
    ) {
        self.urlSession = urlSession
        self.webLoaderFactory = webLoaderFactory
    }

    public func resolveMedia(
        _ item: WebMediaInfo,
        requestContext: WebMediaRequestContext = .init()
    ) async throws -> ResolvedWebMedia {
        guard item.sourceURL != nil else {
            throw PlaybackError.unsupportedSource
        }

        if let resolved = await resolveDirectMedia(item, requestContext: requestContext, method: .direct) {
            return resolved
        }

        if item.pageURL != nil, webLoaderFactory != nil {
            return try await resolveViaFallback(item, requestContext: requestContext)
        }

        if item.isBlobSource || item.isDataSource {
            throw PlaybackError.fallbackUnavailable
        }

        throw PlaybackError.couldNotDeterminePlayableMedia
    }

    public static func getMimeType(
        _ url: URL,
        requestContext: WebMediaRequestContext = .init(),
        using session: URLSession = .shared
    ) async -> String? {
        switch url.scheme?.lowercased() {
        case "http", "https":
            break
        default:
            return nil
        }

        let probeRequests = [
            makeProbeRequest(
                url: url,
                method: "HEAD",
                requestContext: requestContext
            ),
            makeProbeRequest(
                url: url,
                method: "GET",
                requestContext: requestContext,
                range: "bytes=0-1"
            ),
        ]

        for request in probeRequests {
            if let mimeType = await probeMimeType(for: request, using: session) {
                return mimeType
            }
        }

        return nil
    }

    private func resolveViaFallback(
        _ item: WebMediaInfo,
        requestContext: WebMediaRequestContext
    ) async throws -> ResolvedWebMedia {
        guard let pageURL = item.pageURL,
              let webLoaderFactory
        else {
            throw PlaybackError.fallbackUnavailable
        }

        let loader = webLoaderFactory.makeWebLoader()
        defer { loader.stop() }
        guard let fallbackItem = await loader.load(url: pageURL) else {
            throw PlaybackError.fallbackUnavailable
        }
        guard let resolved = await resolveDirectMedia(
            fallbackItem,
            requestContext: requestContext,
            method: .fallback
        ) else {
            throw PlaybackError.fallbackDidNotResolvePlayableMedia
        }

        return resolved
    }

    private func resolveDirectMedia(
        _ item: WebMediaInfo,
        requestContext: WebMediaRequestContext,
        method: WebMediaResolutionMethod
    ) async -> ResolvedWebMedia? {
        guard let url = item.sourceURL,
              item.isBlobSource == false,
              item.isDataSource == false
        else {
            return nil
        }

        let mimeType = await Self.getMimeType(url, requestContext: requestContext, using: urlSession)
            ?? Self.normalizedMimeType(item.mimeType)

        guard mimeType != nil || item.isHTTPSource == false else {
            return nil
        }

        return ResolvedWebMedia(
            mediaInfo: item,
            url: url,
            mimeType: mimeType,
            requestHeaders: requestContext.headers,
            resolutionMethod: method
        )
    }

    private static func normalizedMimeType(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func makeProbeRequest(
        url: URL,
        method: String,
        requestContext: WebMediaRequestContext,
        range: String? = nil
    ) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = method
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Playback-Session-Id")
        if let range {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        for (name, value) in requestContext.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private static func probeMimeType(
        for request: URLRequest,
        using session: URLSession
    ) async -> String? {
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return nil
            }
            guard response.statusCode == 302 || (200...299).contains(response.statusCode) else {
                return nil
            }
            return normalizedMimeType(response.value(forHTTPHeaderField: "Content-Type"))
        } catch {
            return nil
        }
    }
}
