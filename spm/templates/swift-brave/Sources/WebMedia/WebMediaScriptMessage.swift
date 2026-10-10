import Foundation

public struct WebMediaReadyState: Codable, Hashable, Sendable {
    public let state: String

    public init(state: String) {
        self.state = state
    }

    public var isCancellation: Bool {
        state == "cancel"
    }

    public static func decode(from body: Any) -> WebMediaReadyState? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

public enum WebMediaPlaybackEventName: String, Codable, CaseIterable, Sendable {
    case play
    case pause
    case seeking
    case seeked
    case timeupdate
    case ratechange
    case volumechange
    case waiting
    case playing
    case stalled
    case ended
    case loadedmetadata
    case durationchange
    case emptied
    case error
    case enterPictureInPicture = "enterpictureinpicture"
    case leavePictureInPicture = "leavepictureinpicture"
    case presentationModeChanged = "presentationmodechanged"
    case heartbeat
}

public enum WebMediaPlaybackPresentationMode: String, Codable, CaseIterable, Sendable {
    case inline
    case fullscreen
    case pictureInPicture
    case unknown

    public init(rawPresentationMode: String?) {
        switch rawPresentationMode?.lowercased() {
        case "inline":
            self = .inline
        case "fullscreen", "full-screen":
            self = .fullscreen
        case "pictureinpicture", "picture-in-picture", "pip":
            self = .pictureInPicture
        default:
            self = .unknown
        }
    }
}

public struct WebMediaPlaybackSnapshot: Codable, Hashable, Sendable {
    public let tagId: String
    public let pageSrc: String
    public let pageTitle: String
    public let src: String
    public let currentSrc: String
    public let mimeType: String
    public let mediaType: WebMediaKind
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    public let paused: Bool
    public let ended: Bool
    public let playbackRate: Double
    public let muted: Bool
    public let volume: Double
    public let readyState: Int
    public let networkState: Int
    public let presentationMode: WebMediaPlaybackPresentationMode
    public let isInvisible: Bool

    public var effectiveSource: String {
        currentSrc.isEmpty ? src : currentSrc
    }

    public var pageLookupKey: String {
        WebMediaInfo.pageLookupKey(for: pageSrc)
    }

    public init(
        tagId: String,
        pageSrc: String,
        pageTitle: String,
        src: String,
        currentSrc: String,
        mimeType: String,
        mediaType: WebMediaKind,
        currentTime: TimeInterval,
        duration: TimeInterval,
        paused: Bool,
        ended: Bool,
        playbackRate: Double,
        muted: Bool,
        volume: Double,
        readyState: Int,
        networkState: Int,
        presentationMode: WebMediaPlaybackPresentationMode,
        isInvisible: Bool
    ) {
        self.tagId = tagId
        self.pageSrc = pageSrc
        self.pageTitle = pageTitle
        self.src = WebMediaInfo.fixSchemelessURLs(src: src, pageSrc: pageSrc)
        self.currentSrc = WebMediaInfo.fixSchemelessURLs(src: currentSrc, pageSrc: pageSrc)
        self.mimeType = mimeType
        self.mediaType = mediaType
        self.currentTime = currentTime
        self.duration = duration
        self.paused = paused
        self.ended = ended
        self.playbackRate = playbackRate
        self.muted = muted
        self.volume = volume
        self.readyState = readyState
        self.networkState = networkState
        self.presentationMode = presentationMode
        self.isInvisible = isInvisible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pageSrc = try container.decode(String.self, forKey: .pageSrc)
        let src = try container.decodeIfPresent(String.self, forKey: .src) ?? ""
        let currentSrc = try container.decodeIfPresent(String.self, forKey: .currentSrc) ?? ""
        let mediaType = WebMediaKind(
            rawValue: try container.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        ) ?? .unknown
        let presentationMode = WebMediaPlaybackPresentationMode(
            rawPresentationMode: try container.decodeIfPresent(String.self, forKey: .presentationMode)
        )

        self.init(
            tagId: try container.decodeIfPresent(String.self, forKey: .tagId) ?? "",
            pageSrc: pageSrc,
            pageTitle: try container.decodeIfPresent(String.self, forKey: .pageTitle) ?? "",
            src: src,
            currentSrc: currentSrc,
            mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "",
            mediaType: mediaType,
            currentTime: try container.decodeIfPresent(TimeInterval.self, forKey: .currentTime) ?? 0,
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0,
            paused: try container.decodeIfPresent(Bool.self, forKey: .paused) ?? true,
            ended: try container.decodeIfPresent(Bool.self, forKey: .ended) ?? false,
            playbackRate: try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1,
            muted: try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false,
            volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1,
            readyState: try container.decodeIfPresent(Int.self, forKey: .readyState) ?? 0,
            networkState: try container.decodeIfPresent(Int.self, forKey: .networkState) ?? 0,
            presentationMode: presentationMode,
            isInvisible: try container.decodeIfPresent(Bool.self, forKey: .isInvisible) ?? false
        )
    }

    public static func decode(from body: Any) -> WebMediaPlaybackSnapshot? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

public struct WebMediaPlaybackEvent: Codable, Hashable, Sendable {
    public let eventName: WebMediaPlaybackEventName
    public let snapshot: WebMediaPlaybackSnapshot

    public init(
        eventName: WebMediaPlaybackEventName,
        snapshot: WebMediaPlaybackSnapshot
    ) {
        self.eventName = eventName
        self.snapshot = snapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.eventName = try container.decode(WebMediaPlaybackEventName.self, forKey: .eventName)
        self.snapshot = try WebMediaPlaybackSnapshot(from: decoder)
    }

    public static func decode(from body: Any) -> WebMediaPlaybackEvent? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

public enum WebMediaScriptMessage: Hashable, Sendable {
    case readyState(WebMediaReadyState)
    case media(WebMediaInfo)
    case playback(WebMediaPlaybackEvent)
}

public enum WebMediaScriptMessageDecoder {
    public static func decode(
        body: Any,
        expectingSecurityToken securityToken: String? = nil
    ) -> WebMediaScriptMessage? {
        guard let payload = body as? [String: Any] else {
            return nil
        }

        if let securityToken,
           payload["securityToken"] as? String != securityToken {
            return nil
        }

        if payload["state"] != nil,
           let readyState = WebMediaReadyState.decode(from: payload) {
            return .readyState(readyState)
        }

        if payload["messageKind"] as? String == "playback",
           let playbackEvent = WebMediaPlaybackEvent.decode(from: payload) {
            return .playback(playbackEvent)
        }

        if let info = WebMediaInfo.decode(from: payload) {
            return .media(info)
        }

        return nil
    }

}
