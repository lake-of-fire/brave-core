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

    public var containerKind: WebMediaContainerKind {
        let resolvedType = WebMediaMimeTypeDetector(mimeType: mimeType).mimeType
        if resolvedType == "application/vnd.apple.mpegurl"
            || resolvedType == "application/x-mpegurl"
            || resolvedType == "audio/mpegurl"
            || resolvedType == "audio/x-mpegurl"
            || url.pathExtension.lowercased() == "m3u8" {
            return .hls
        }
        if let resolvedType, resolvedType.hasPrefix("audio/") || resolvedType.hasPrefix("video/")
            || resolvedType == "application/ogg" {
            return .file
        }
        return mediaInfo.containerKind
    }

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
        try Task.checkCancellation()
        guard item.sourceURL != nil else {
            throw PlaybackError.unsupportedSource
        }

        if let resolved = await resolveDirectMedia(item, requestContext: requestContext, method: .direct) {
            try Task.checkCancellation()
            return resolved
        }

        try Task.checkCancellation()

        if item.pageURL != nil, webLoaderFactory != nil {
            return try await resolveViaFallback(item, requestContext: requestContext)
        }

        if item.isBlobSource || item.isDataSource {
            throw PlaybackError.fallbackUnavailable
        }

        throw PlaybackError.couldNotDeterminePlayableMedia
    }

    private enum MediaProbeResult: Sendable {
        case media(String)
        case nonMedia
        case unavailable
    }

    public static func getMimeType(
        _ url: URL,
        requestContext: WebMediaRequestContext = .init(),
        using session: URLSession = .shared
    ) async -> String? {
        if case .media(let mimeType) = await probeMediaType(url, requestContext: requestContext, using: session) {
            return mimeType
        }
        return nil
    }

    private static func probeMediaType(
        _ url: URL,
        requestContext: WebMediaRequestContext,
        using session: URLSession
    ) async -> MediaProbeResult {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .unavailable }
        let requests = [
            makeProbeRequest(url: url, method: "HEAD", requestContext: requestContext),
            makeProbeRequest(url: url, method: "GET", requestContext: requestContext, range: "bytes=0-4095"),
        ]
        var foundNonMedia = false
        for request in requests {
            guard !Task.isCancelled else { return .unavailable }
            switch await probeMimeType(for: request, using: session) {
            case .media(let mimeType): return .media(mimeType)
            case .nonMedia: foundNonMedia = true
            case .unavailable: break
            }
        }
        return foundNonMedia ? .nonMedia : .unavailable
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
            try Task.checkCancellation()
            throw PlaybackError.fallbackUnavailable
        }
        try Task.checkCancellation()
        guard fallbackItem.referencesSameResource(as: item) else {
            throw PlaybackError.fallbackDidNotResolvePlayableMedia
        }
        guard let resolved = await resolveDirectMedia(
            fallbackItem,
            requestContext: requestContext,
            method: .fallback
        ) else {
            throw PlaybackError.fallbackDidNotResolvePlayableMedia
        }

        // A resolver may find a new transport URL; it does not own a new media
        // identity. Keep the requested resource as the presentation owner.
        return ResolvedWebMedia(mediaInfo: item, url: resolved.url, mimeType: resolved.mimeType,
                                requestHeaders: resolved.requestHeaders, resolutionMethod: .fallback)
    }

    private func resolveDirectMedia(
        _ item: WebMediaInfo,
        requestContext: WebMediaRequestContext,
        method: WebMediaResolutionMethod
    ) async -> ResolvedWebMedia? {
        guard let url = item.sourceURL,
              ["http", "https", "file"].contains(url.scheme?.lowercased() ?? ""),
              item.isBlobSource == false,
              item.isDataSource == false
        else {
            return nil
        }

        let mimeType: String?
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            mimeType = Self.playableMimeType(Self.normalizedMimeType(item.mimeType))
                ?? Self.playableMimeType(WebMediaMimeTypeDetector(url: url).mimeType)
        } else {
            switch await Self.probeMediaType(url, requestContext: requestContext, using: urlSession) {
            case .media(let resolved): mimeType = resolved
            case .nonMedia:
                // A stale detector hint cannot turn a login/watch HTML page or
                // a JSON error response into a playable media resource.
                return nil
            case .unavailable:
                mimeType = Self.playableMimeType(Self.normalizedMimeType(item.mimeType))
                    ?? Self.playableMimeType(WebMediaMimeTypeDetector(url: url).mimeType)
                guard mimeType != nil else { return nil }
            }
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
        return trimmed?.isEmpty == false ? trimmed?.lowercased() : nil
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
        for (name, value) in requestContext.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(range, forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private static func playableMimeType(_ mimeType: String?) -> String? {
        guard let mimeType,
              (mimeType.hasPrefix("audio/") && mimeType.count > 6)
                || (mimeType.hasPrefix("video/") && mimeType.count > 6)
                || mimeType == "application/vnd.apple.mpegurl" || mimeType == "application/x-mpegurl"
                || mimeType == "application/ogg" else { return nil }
        return mimeType
    }

    private static func probeMimeType(
        for request: URLRequest,
        using session: URLSession
    ) async -> MediaProbeResult {
        do {
            guard let url = request.url else { return .unavailable }
            let (bytes, response) = try await session.bytes(for: request,
                delegate: WebMediaRequestRedirectPolicy(url: url, maximumRedirects: 4))
            // A server may ignore Range. Never read more than the bounded prefix,
            // and cancel the transport even when the MIME is known from headers.
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { return .unavailable }
            guard (200...299).contains(response.statusCode) else {
                return request.httpMethod == "HEAD" && [405, 501].contains(response.statusCode)
                    ? .unavailable : .nonMedia
            }
            let mimeType = normalizedMimeType(response.value(forHTTPHeaderField: "Content-Type"))
            if let playable = playableMimeType(mimeType) { return .media(playable) }
            let declaresDocument = mimeType.map {
                $0.hasPrefix("text/") || $0 == "application/json" || $0.hasSuffix("+json")
                    || $0 == "application/xml" || $0.hasSuffix("+xml")
            } ?? false
            guard request.httpMethod != "HEAD" else { return declaresDocument ? .nonMedia : .unavailable }
            var prefix = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                prefix.append(byte)
                if prefix.count >= 4096 { break }
            }
            if let detected = WebMediaMimeTypeDetector(data: prefix).mimeType { return .media(detected) }
            let text = String(data: prefix, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
                .lowercased()
            let isDocument = text.map {
                $0.hasPrefix("<!doctype") || $0.hasPrefix("<html") || $0.hasPrefix("<?xml")
                    || $0.hasPrefix("{") || $0.hasPrefix("[") || $0.hasPrefix("webvtt")
            } ?? false
            return declaresDocument || isDocument || prefix.isEmpty ? .nonMedia : .unavailable
        } catch {
            return .unavailable
        }
    }
}
