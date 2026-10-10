import Foundation

public enum WebMediaKind: String, Codable, CaseIterable, Sendable {
    case video
    case audio
    case unknown
}

public enum WebMediaContainerKind: String, Codable, CaseIterable, Sendable {
    case hls
    case file
    case unknown
}

public enum WebMediaPlaybackKind: String, Codable, CaseIterable, Sendable {
    case audioOnly
    case video
    case unknown
}

public struct WebMediaInfo: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var src: String
    public var pageSrc: String
    public var pageTitle: String
    public var mimeType: String
    public var duration: TimeInterval
    public var detected: Bool
    public var tagId: String
    public var isInvisible: Bool
    /// Set by native provider admission after matching the player resource to
    /// its frame. JavaScript detector payloads cannot supply this authority.
    public var durableResourceIdentity: String?

    public var id: String {
        tagId
    }

    public var sourceURL: URL? {
        URL(string: src)
    }

    public var pageURL: URL? {
        URL(string: pageSrc)
    }

    public var pageLookupKey: String {
        Self.pageLookupKey(for: pageSrc)
    }

    public var candidateLookupKey: String {
        Self.candidateLookupKey(
            pageSrc: pageSrc,
            tagId: tagId,
            name: name,
            duration: duration
        )
    }

    /// Durable identity of the page's media resource. DOM tags, display names
    /// and measured durations can change on every visit and are not storage keys.
    public var resourceLookupKey: String {
        if let identity = durableResourceIdentity {
            if identity == sourceBasedResourceLookupKey { return identity }
            if identity.hasPrefix("provider:youtube:"),
               let videoID = identity.split(separator: ":").last.map(String.init),
               identity == "provider:youtube:\(videoID)",
               (Self.youtubeVideoID(in: pageURL) == videoID || Self.youtubeVideoID(in: sourceURL) == videoID),
               Self.isYouTubeMediaSource(sourceURL, providerPage: pageURL) {
                return "provider:youtube:\(videoID)"
            }
        }
        return sourceBasedResourceLookupKey
    }

    public var sourceBasedResourceLookupKey: String {
        Self.resourceLookupKey(pageSrc: pageSrc, source: src)
    }

    public func referencesSameResource(as other: WebMediaInfo) -> Bool {
        resourceLookupKey == other.resourceLookupKey
            || sourceBasedResourceLookupKey == other.sourceBasedResourceLookupKey
    }

    /// Identifies one live element/resource binding. Use this for playback
    /// receipts and document fencing, never for offline or transcript reuse.
    public var playbackInstanceLookupKey: String {
        Self.resourceLookupKey(candidateLookupKey: candidateLookupKey, source: src)
    }

    public var preferredDisplayName: String {
        let candidates = [name, pageTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return candidates.first ?? "Media"
    }

    public var normalizedMimeType: String? {
        let trimmed = mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    public var containerKind: WebMediaContainerKind {
        if Self.hlsMimeTypes.contains(normalizedMimeType ?? "")
            || sourceURL?.pathExtension.lowercased() == "m3u8" {
            return .hls
        }

        switch sourceURL?.pathExtension.lowercased() {
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "mp4", "m4v", "mov", "webm":
            return .file
        default:
            return normalizedMimeType == nil ? .unknown : .file
        }
    }

    public var kind: WebMediaKind {
        let normalizedMimeType = self.normalizedMimeType ?? ""
        if normalizedMimeType.hasPrefix("audio/") || normalizedMimeType == "audio" {
            return .audio
        }
        if normalizedMimeType.hasPrefix("video/") || normalizedMimeType == "video" {
            return .video
        }
        if Self.hlsMimeTypes.contains(normalizedMimeType) {
            return .unknown
        }

        switch sourceURL?.pathExtension.lowercased() {
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus":
            return .audio
        case "mp4", "m4v", "mov", "webm":
            return .video
        case "m3u8":
            return .unknown
        default:
            return .unknown
        }
    }

    public var playbackKind: WebMediaPlaybackKind {
        switch kind {
        case .audio:
            return .audioOnly
        case .video:
            return .video
        case .unknown:
            break
        }

        guard containerKind == .hls else {
            return .unknown
        }

        let context = [name, pageTitle, src]
            .joined(separator: " ")
            .lowercased()

        if Self.audioOnlyMarkers.contains(where: { context.contains($0) }) {
            return .audioOnly
        }
        if Self.videoMarkers.contains(where: { context.contains($0) }) {
            return .video
        }

        return .unknown
    }

    public var isLikelyAudioOnly: Bool {
        playbackKind == .audioOnly
    }

    public var isLikelyAdvertisement: Bool {
        let context = [name, pageTitle, src]
            .joined(separator: " ")
            .lowercased()
        return Self.advertisementMarkers.contains(where: { context.contains($0) })
    }

    public var isBlobSource: Bool {
        src.hasPrefix("blob:")
    }

    public var isDataSource: Bool {
        src.hasPrefix("data:")
    }

    public var isHTTPSource: Bool {
        guard let scheme = sourceURL?.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    public init(pageSrc: String) {
        self.init(
            name: "",
            src: "",
            pageSrc: pageSrc,
            pageTitle: "",
            mimeType: "",
            duration: 0,
            detected: false,
            tagId: UUID().uuidString,
            isInvisible: false
        )
    }

    public init(
        name: String,
        src: String,
        pageSrc: String,
        pageTitle: String,
        mimeType: String,
        duration: TimeInterval,
        detected: Bool,
        tagId: String,
        isInvisible: Bool,
        durableResourceIdentity: String? = nil
    ) {
        self.name = name
        self.src = Self.fixSchemelessURLs(src: src, pageSrc: pageSrc)
        self.pageSrc = pageSrc
        self.pageTitle = pageTitle
        self.mimeType = mimeType
        self.duration = duration
        self.detected = detected
        self.tagId = tagId.isEmpty ? UUID().uuidString : tagId
        self.isInvisible = isInvisible
        self.durableResourceIdentity = durableResourceIdentity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let src = try container.decodeIfPresent(String.self, forKey: .src) ?? ""
        let pageSrc = try container.decode(String.self, forKey: .pageSrc)

        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.src = Self.fixSchemelessURLs(src: src, pageSrc: pageSrc)
        self.pageSrc = pageSrc
        self.pageTitle = try container.decodeIfPresent(String.self, forKey: .pageTitle) ?? ""
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        self.detected = try container.decodeIfPresent(Bool.self, forKey: .detected) ?? false
        self.tagId = try container.decodeIfPresent(String.self, forKey: .tagId) ?? UUID().uuidString
        self.isInvisible = try container.decodeIfPresent(Bool.self, forKey: .isInvisible) ?? false
        self.durableResourceIdentity = try container.decodeIfPresent(String.self, forKey: .durableResourceIdentity)
    }

    public static func decode(from body: Any) -> WebMediaInfo? {
        guard var body = body as? [String: Any] else { return nil }
        body.removeValue(forKey: "durableResourceIdentity")
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public static func fixSchemelessURLs(src: String, pageSrc: String) -> String {
        if src.hasPrefix("//") {
            return "\(URL(string: pageSrc)?.scheme ?? "https"):\(src)"
        }
        if src.hasPrefix("/"),
           let url = URL(string: src, relativeTo: URL(string: pageSrc))?.absoluteString {
            return url
        }
        return src
    }

    public static func pageLookupKey(for pageSrc: String) -> String {
        canonicalSourceLookupKey(for: pageSrc)
    }

    public static func candidateLookupKey(
        pageSrc: String,
        tagId: String,
        name: String,
        duration: TimeInterval
    ) -> String {
        let pageKey = pageLookupKey(for: pageSrc)
        if tagId.isEmpty == false {
            return "\(pageKey)::\(tagId)"
        }

        let sanitizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let roundedDuration = duration.isFinite && duration >= 0 && duration < Double(Int.max)
            ? Int(duration.rounded(.down)) : 0
        return "\(pageKey)::\(sanitizedName)::\(roundedDuration)"
    }

    public static func resourceLookupKey(pageSrc: String, source: String) -> String {
        // Length prefixes keep arbitrary URL contents from colliding with a
        // separator. Query parameters remain significant, including signed URLs.
        let page = pageLookupKey(for: pageSrc)
        let resource = canonicalSourceLookupKey(for: source)
        return "web-media-resource-v2:\(page.utf8.count):\(page)\(resource.utf8.count):\(resource)"
    }

    /// Compatibility form for live playback bindings saved by earlier clients.
    public static func resourceLookupKey(candidateLookupKey: String, source: String) -> String {
        "\(candidateLookupKey)\u{1F}\(canonicalSourceLookupKey(for: source))"
    }

    public static func canonicalSourceLookupKey(for source: String) -> String {
        guard var components = URLComponents(string: source) else {
            return source.split(separator: "#", maxSplits: 1).first.map(String.init) ?? source
        }

        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        return components.string ?? source
    }

    private static func youtubeVideoID(in url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
               "youtube-nocookie.com", "www.youtube-nocookie.com", "youtu.be", "www.youtu.be"].contains(host) else { return nil }
        let segments = url.path.split(separator: "/")
        let videoID: String?
        if host == "youtu.be" || host == "www.youtu.be" {
            videoID = segments.count == 1 ? String(segments[0]) : nil
        } else if segments.count == 2, ["embed", "shorts", "live"].contains(String(segments[0])) {
            videoID = String(segments[1])
        } else if url.path == "/watch" {
            let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "v" } ?? []
            videoID = values.count == 1 ? values[0].value : nil
        } else { videoID = nil }
        guard let videoID, videoID.utf8.count == 11,
              videoID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return videoID
    }

    private static func isYouTubeMediaSource(_ source: URL?, providerPage: URL?) -> Bool {
        guard let source else { return false }
        if source.scheme?.lowercased() == "blob" {
            guard let origin = URL(string: String(source.absoluteString.dropFirst(5))),
                  origin.scheme?.lowercased() == "https", origin.user == nil, origin.password == nil,
                  origin.host?.lowercased() == providerPage?.host?.lowercased(),
                  (origin.port ?? 443) == 443 else { return false }
            return true
        }
        guard source.scheme?.lowercased() == "https", source.user == nil, source.password == nil,
              (source.port ?? 443) == 443, let host = source.host?.lowercased() else { return false }
        return host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
            || ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
                "youtube-nocookie.com", "www.youtube-nocookie.com"].contains(host)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case src
        case pageSrc
        case pageTitle
        case mimeType
        case duration
        case detected
        case tagId
        case isInvisible = "invisible"
        case durableResourceIdentity
    }

    private static let hlsMimeTypes: Set<String> = [
        "application/vnd.apple.mpegurl",
        "application/x-mpegurl",
        "audio/mpegurl",
        "audio/x-mpegurl",
    ]

    private static let audioOnlyMarkers: Set<String> = [
        "/audio/",
        " audio ",
        "audio-only",
        "audio_only",
        "podcast",
        "music",
        "song",
        "radio",
        "voice",
    ]

    private static let videoMarkers: Set<String> = [
        "/video/",
        " video ",
        "video-only",
        "video_only",
        "watch",
        "movie",
        "episode",
        "trailer",
        "clip",
        "livestream",
        "live stream",
    ]

    private static let advertisementMarkers: Set<String> = [
        "doubleclick",
        "googlesyndication",
        "googletagmanager",
        "googleads",
        "adservice",
        "adsystem",
        "imasdk",
        "preroll",
        "pre-roll",
        "midroll",
        "mid-roll",
        "vast",
        "/ads/",
        "_ads",
        "-ads",
        "advertisement",
        "sponsor",
    ]
}
