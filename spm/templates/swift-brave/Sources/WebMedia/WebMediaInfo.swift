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

    /// Identifies the concrete page media resource without changing the
    /// DOM-oriented candidate key used by page-level callers.
    public var resourceLookupKey: String {
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
        isInvisible: Bool
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
    }

    public static func decode(from body: Any) -> WebMediaInfo? {
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
        guard var components = URLComponents(string: pageSrc) else {
            return pageSrc.split(separator: "#", maxSplits: 1).first.map(String.init) ?? pageSrc
        }

        components.fragment = nil
        return components.string ?? pageSrc
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
        let roundedDuration = Int(duration.rounded())
        return "\(pageKey)::\(sanitizedName)::\(roundedDuration)"
    }

    public static func resourceLookupKey(candidateLookupKey: String, source: String) -> String {
        "\(candidateLookupKey)\u{1F}\(canonicalSourceLookupKey(for: source))"
    }

    public static func canonicalSourceLookupKey(for source: String) -> String {
        guard var components = URLComponents(string: source) else {
            return source.split(separator: "#", maxSplits: 1).first.map(String.init) ?? source
        }

        components.fragment = nil
        return components.string ?? source
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
    }

    private static let hlsMimeTypes: Set<String> = [
        "application/vnd.apple.mpegurl",
        "application/x-mpegurl",
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
