import Foundation
import WebKit
import SwiftUIWebView

public enum WebMediaCaptureMediaKind: String, Codable, CaseIterable, Sendable {
    case video
    case audio
    case unknown

    init(_ value: WebMediaKind) {
        switch value {
        case .video:
            self = .video
        case .audio:
            self = .audio
        case .unknown:
            self = .unknown
        }
    }

    var rawValueCore: WebMediaKind {
        switch self {
        case .video:
            return .video
        case .audio:
            return .audio
        case .unknown:
            return .unknown
        }
    }
}

public enum WebMediaCapturePlaybackKind: String, Codable, CaseIterable, Sendable {
    case audioOnly
    case video
    case unknown

    init(_ value: WebMediaPlaybackKind) {
        switch value {
        case .audioOnly:
            self = .audioOnly
        case .video:
            self = .video
        case .unknown:
            self = .unknown
        }
    }

    var rawValueCore: WebMediaPlaybackKind {
        switch self {
        case .audioOnly:
            return .audioOnly
        case .video:
            return .video
        case .unknown:
            return .unknown
        }
    }
}

public struct WebMediaCaptureReadyState: Codable, Hashable, Sendable {
    let readyState: WebMediaReadyState

    public init(state: String) {
        self.readyState = WebMediaReadyState(state: state)
    }

    init(_ readyState: WebMediaReadyState) {
        self.readyState = readyState
    }

    public var state: String { readyState.state }
    public var isCancellation: Bool { readyState.isCancellation }

    var rawValue: WebMediaReadyState { readyState }
}

public enum WebMediaCapturePlaybackEventName: String, Codable, CaseIterable, Sendable {
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

    init(_ value: WebMediaPlaybackEventName) {
        self = Self(rawValue: value.rawValue) ?? .heartbeat
    }

    var rawValueCore: WebMediaPlaybackEventName {
        WebMediaPlaybackEventName(rawValue: rawValue) ?? .heartbeat
    }
}

public enum WebMediaCapturePlaybackPresentationMode: String, Codable, CaseIterable, Sendable {
    case inline
    case fullscreen
    case pictureInPicture
    case unknown

    init(_ value: WebMediaPlaybackPresentationMode) {
        self = Self(rawValue: value.rawValue) ?? .unknown
    }

    var rawValueCore: WebMediaPlaybackPresentationMode {
        WebMediaPlaybackPresentationMode(rawValue: rawValue) ?? .unknown
    }
}

public struct WebMediaCapturePlaybackSnapshot: Codable, Hashable, Sendable {
    let playbackSnapshot: WebMediaPlaybackSnapshot

    public init(
        tagID: String,
        pageURL: URL?,
        pageTitle: String,
        sourceURL: URL?,
        currentSourceURL: URL?,
        mimeType: String,
        mediaType: WebMediaCaptureMediaKind,
        currentTime: TimeInterval,
        duration: TimeInterval,
        paused: Bool,
        ended: Bool,
        playbackRate: Double,
        muted: Bool,
        volume: Double,
        readyState: Int,
        networkState: Int,
        presentationMode: WebMediaCapturePlaybackPresentationMode,
        isInvisible: Bool
    ) {
        self.playbackSnapshot = WebMediaPlaybackSnapshot(
            tagId: tagID,
            pageSrc: pageURL?.absoluteString ?? "",
            pageTitle: pageTitle,
            src: sourceURL?.absoluteString ?? "",
            currentSrc: currentSourceURL?.absoluteString ?? "",
            mimeType: mimeType,
            mediaType: mediaType.rawValueCore,
            currentTime: currentTime,
            duration: duration,
            paused: paused,
            ended: ended,
            playbackRate: playbackRate,
            muted: muted,
            volume: volume,
            readyState: readyState,
            networkState: networkState,
            presentationMode: presentationMode.rawValueCore,
            isInvisible: isInvisible
        )
    }

    init(_ playbackSnapshot: WebMediaPlaybackSnapshot) {
        self.playbackSnapshot = playbackSnapshot
    }

    public var tagID: String { playbackSnapshot.tagId }
    public var pageURL: URL? { URL(string: playbackSnapshot.pageSrc) }
    public var pageTitle: String { playbackSnapshot.pageTitle }
    public var sourceURL: URL? { URL(string: playbackSnapshot.src) }
    public var currentSourceURL: URL? { URL(string: playbackSnapshot.currentSrc) }
    public var mimeType: String { playbackSnapshot.mimeType }
    public var mediaType: WebMediaCaptureMediaKind { .init(playbackSnapshot.mediaType) }
    public var currentTime: TimeInterval { playbackSnapshot.currentTime }
    public var duration: TimeInterval { playbackSnapshot.duration }
    public var paused: Bool { playbackSnapshot.paused }
    public var ended: Bool { playbackSnapshot.ended }
    public var playbackRate: Double { playbackSnapshot.playbackRate }
    public var muted: Bool { playbackSnapshot.muted }
    public var volume: Double { playbackSnapshot.volume }
    public var readyState: Int { playbackSnapshot.readyState }
    public var networkState: Int { playbackSnapshot.networkState }
    public var presentationMode: WebMediaCapturePlaybackPresentationMode { .init(playbackSnapshot.presentationMode) }
    public var isInvisible: Bool { playbackSnapshot.isInvisible }
    public var effectiveSource: String { playbackSnapshot.effectiveSource }

    var rawValue: WebMediaPlaybackSnapshot { playbackSnapshot }
}

public struct WebMediaCapturePlaybackEvent: Codable, Hashable, Sendable {
    let playbackEvent: WebMediaPlaybackEvent

    public init(
        eventName: WebMediaCapturePlaybackEventName,
        snapshot: WebMediaCapturePlaybackSnapshot
    ) {
        self.playbackEvent = WebMediaPlaybackEvent(
            eventName: eventName.rawValueCore,
            snapshot: snapshot.rawValue
        )
    }

    init(_ playbackEvent: WebMediaPlaybackEvent) {
        self.playbackEvent = playbackEvent
    }

    public var eventName: WebMediaCapturePlaybackEventName { .init(playbackEvent.eventName) }
    public var snapshot: WebMediaCapturePlaybackSnapshot { .init(playbackEvent.snapshot) }

    var rawValue: WebMediaPlaybackEvent { playbackEvent }
}

public struct WebMediaCaptureScriptConfiguration: Hashable, Sendable {
    let scriptConfiguration: WebMediaScriptConfiguration

    public init(
        messageHandlerName: String,
        securityToken: String = UUID().uuidString,
        namespaceToken: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) {
        self.scriptConfiguration = WebMediaScriptConfiguration(
            messageHandlerName: messageHandlerName,
            securityToken: securityToken,
            namespaceToken: namespaceToken
        )
    }

    init(_ scriptConfiguration: WebMediaScriptConfiguration) {
        self.scriptConfiguration = scriptConfiguration
    }

    public var messageHandlerName: String { scriptConfiguration.messageHandlerName }
    public var securityToken: String { scriptConfiguration.securityToken }
    public var tagAttributeName: String { scriptConfiguration.tagAttributeName }
    public var sendMessageTimeoutName: String { scriptConfiguration.sendMessageTimeoutName }
    public var longPressFunctionName: String { scriptConfiguration.longPressFunctionName }
    public var processDocumentLoadFunctionName: String { scriptConfiguration.processDocumentLoadFunctionName }
    public var currentTimeFunctionName: String { scriptConfiguration.currentTimeFunctionName }
    public var stopPlaybackFunctionName: String { scriptConfiguration.stopPlaybackFunctionName }
    public var telemetryAttachedName: String { scriptConfiguration.telemetryAttachedName }
    public var telemetryHeartbeatName: String { scriptConfiguration.telemetryHeartbeatName }

    var rawValue: WebMediaScriptConfiguration { scriptConfiguration }
}

public enum WebMediaCaptureResolutionMethod: String, Hashable, Codable, Sendable {
    case direct
    case fallback

    init(_ value: WebMediaResolutionMethod) {
        self = Self(rawValue: value.rawValue) ?? .direct
    }

    var rawValueCore: WebMediaResolutionMethod {
        WebMediaResolutionMethod(rawValue: rawValue) ?? .direct
    }
}

public struct WebMediaCaptureCandidate: Hashable, Identifiable, Sendable {
    let mediaInfo: WebMediaInfo

    public init(
        name: String,
        sourceURL: URL?,
        pageURL: URL?,
        pageTitle: String,
        mimeType: String,
        duration: TimeInterval,
        detected: Bool,
        tagID: String,
        isInvisible: Bool
    ) {
        self.mediaInfo = WebMediaInfo(
            name: name,
            src: sourceURL?.absoluteString ?? "",
            pageSrc: pageURL?.absoluteString ?? "",
            pageTitle: pageTitle,
            mimeType: mimeType,
            duration: duration,
            detected: detected,
            tagId: tagID,
            isInvisible: isInvisible
        )
    }

    init(_ mediaInfo: WebMediaInfo) {
        self.mediaInfo = mediaInfo
    }

    public var id: String { mediaInfo.id }
    public var name: String { mediaInfo.name }
    public var sourceURL: URL? { mediaInfo.sourceURL }
    public var pageURL: URL? { mediaInfo.pageURL }
    public var pageTitle: String { mediaInfo.pageTitle }
    public var mimeType: String { mediaInfo.mimeType }
    public var duration: TimeInterval { mediaInfo.duration }
    public var detected: Bool { mediaInfo.detected }
    public var tagID: String { mediaInfo.tagId }
    public var isInvisible: Bool { mediaInfo.isInvisible }
    public var preferredDisplayName: String { mediaInfo.preferredDisplayName }
    public var playbackKind: WebMediaCapturePlaybackKind { .init(mediaInfo.playbackKind) }
    public var isBlobLike: Bool { mediaInfo.isBlobSource || mediaInfo.isDataSource }
    public var isLikelyAdvertisement: Bool { mediaInfo.isLikelyAdvertisement }

    var rawValue: WebMediaInfo { mediaInfo }
}

public struct WebMediaCaptureResolvedMedia: Hashable, Sendable {
    let resolvedMedia: ResolvedWebMedia

    public init(
        candidate: WebMediaCaptureCandidate,
        url: URL,
        mimeType: String?,
        requestHeaders: [String: String],
        resolutionMethod: WebMediaCaptureResolutionMethod
    ) {
        self.resolvedMedia = ResolvedWebMedia(
            mediaInfo: candidate.rawValue,
            url: url,
            mimeType: mimeType,
            requestHeaders: requestHeaders,
            resolutionMethod: resolutionMethod.rawValueCore
        )
    }

    init(_ resolvedMedia: ResolvedWebMedia) {
        self.resolvedMedia = resolvedMedia
    }

    public var candidate: WebMediaCaptureCandidate { .init(resolvedMedia.mediaInfo) }
    public var url: URL { resolvedMedia.url }
    public var mimeType: String? { resolvedMedia.mimeType }
    public var requestHeaders: [String: String] { resolvedMedia.requestHeaders }
    public var resolutionMethod: WebMediaCaptureResolutionMethod { .init(resolvedMedia.resolutionMethod) }

    var rawValue: ResolvedWebMedia { resolvedMedia }
}

public struct WebMediaCaptureRequestContext: Hashable, Sendable {
    let requestContext: WebMediaRequestContext

    public init(headers: [String: String] = [:]) {
        self.requestContext = WebMediaRequestContext(headers: headers)
    }

    init(_ requestContext: WebMediaRequestContext) {
        self.requestContext = requestContext
    }

    public var headers: [String: String] { requestContext.headers }

    var rawValue: WebMediaRequestContext { requestContext }
}

public struct WebMediaCaptureWebScriptSet: Sendable {
    let scriptSet: WebMediaScriptSet

    init(_ scriptSet: WebMediaScriptSet) {
        self.scriptSet = scriptSet
    }

    public var userScripts: [WebViewUserScript] { scriptSet.userScripts }
    public var messageHandlerName: String { scriptSet.messageHandlerName }
    public var securityToken: String { scriptSet.securityToken }
    public var processDocumentLoadJavaScript: String { scriptSet.processDocumentLoadJavaScript }

    var rawValue: WebMediaScriptSet { scriptSet }
}

public enum WebMediaCaptureMessage: Hashable, Sendable {
    case readyState(WebMediaCaptureReadyState)
    case candidate(WebMediaCaptureCandidate)
    case playback(WebMediaCapturePlaybackEvent)
}

public enum WebMediaCaptureWebScripts {
    public static func make(
        messageHandlerName: String,
        allowedDomains: Set<String> = [],
        configuration: WebMediaCaptureScriptConfiguration? = nil
    ) throws -> WebMediaCaptureWebScriptSet {
        try .init(
            WebMediaScripts.make(
                messageHandlerName: messageHandlerName,
                allowedDomains: allowedDomains,
                configuration: configuration?.rawValue
            )
        )
    }
}

public enum WebMediaCaptureMessageDecoder {
    public static func decode(
        message: WebViewMessage,
        scriptSet: WebMediaCaptureWebScriptSet
    ) -> WebMediaCaptureMessage? {
        decode(body: message.body, scriptSet: scriptSet)
    }

    public static func decode(
        body: Any,
        scriptSet: WebMediaCaptureWebScriptSet
    ) -> WebMediaCaptureMessage? {
        guard let decoded = WebMediaMessageDecoder.decode(body: body, scriptSet: scriptSet.rawValue) else {
            return nil
        }
        switch decoded {
        case .readyState(let state):
            return .readyState(.init(state))
        case .media(let info):
            return .candidate(.init(info))
        case .playback(let event):
            return .playback(.init(event))
        }
    }
}

public enum WebMediaCaptureCandidateSelector {
    public static func preferredCandidate(
        from candidates: [WebMediaCaptureCandidate],
        preferringAudio: Bool = true
    ) -> WebMediaCaptureCandidate? {
        WebMediaCandidateSelector.preferredCandidate(
            from: candidates.map(\.rawValue),
            preferringAudio: preferringAudio
        ).map(WebMediaCaptureCandidate.init)
    }
}

public enum WebMediaCaptureRequestContextBuilder {
    public static func make(
        userAgent: String? = nil,
        referer: URL? = nil,
        cookies: [HTTPCookie] = []
    ) -> WebMediaCaptureRequestContext {
        .init(
            WebMediaRequestContextBuilder.make(
                userAgent: userAgent,
                referer: referer,
                cookies: cookies
            )
        )
    }

    public static func make(
        webView: WKWebView,
        referer: URL? = nil
    ) async -> WebMediaCaptureRequestContext {
        .init(await WebMediaRequestContextBuilder.make(webView: webView, referer: referer))
    }
}

public enum WebMediaCaptureStorageScope: String, Codable, CaseIterable, Sendable {
    case transient
    case persistent

    init(_ value: WebMediaOfflineStorageScope) {
        switch value {
        case .transient:
            self = .transient
        case .persistent:
            self = .persistent
        }
    }

    var rawValueCore: WebMediaOfflineStorageScope {
        switch self {
        case .transient:
            return .transient
        case .persistent:
            return .persistent
        }
    }
}

public enum WebMediaCaptureRetentionPolicy: String, Codable, CaseIterable, Sendable {
    case persistent
    case manualTransient
    case untilPageChange
    case untilSessionEnds

    init(_ value: WebMediaRetentionPolicy) {
        switch value {
        case .persistent:
            self = .persistent
        case .manualTransient:
            self = .manualTransient
        case .untilPageChange:
            self = .untilPageChange
        case .untilSessionEnds:
            self = .untilSessionEnds
        }
    }

    var rawValueCore: WebMediaRetentionPolicy {
        switch self {
        case .persistent:
            return .persistent
        case .manualTransient:
            return .manualTransient
        case .untilPageChange:
            return .untilPageChange
        case .untilSessionEnds:
            return .untilSessionEnds
        }
    }
}

public struct WebMediaCaptureDownloadProgress: Hashable, Sendable {
    let progress: WebMediaDownloadProgress

    init(_ progress: WebMediaDownloadProgress) {
        self.progress = progress
    }

    public var bytesDownloaded: Int64 { progress.bytesDownloaded }
    public var totalBytesExpected: Int64? { progress.totalBytesExpected }
    public var fractionCompleted: Double { progress.fractionCompleted }
}

public struct WebMediaCaptureStoredMedia: Hashable, Identifiable, Sendable {
    let storedMedia: StoredWebMedia

    init(_ storedMedia: StoredWebMedia) {
        self.storedMedia = storedMedia
    }

    public var id: String { storedMedia.id }
    public var candidate: WebMediaCaptureCandidate { .init(storedMedia.mediaInfo) }
    public var storageScope: WebMediaCaptureStorageScope { .init(storedMedia.storageScope) }
    public var retentionPolicy: WebMediaCaptureRetentionPolicy { .init(storedMedia.retentionPolicy) }
    public var resolvedMediaURL: URL { storedMedia.resolvedMediaURL }
    public var localMediaURL: URL { storedMedia.localMediaURL }
    public var localThumbnailURL: URL? { storedMedia.localThumbnailURL }
    public var mimeType: String? { storedMedia.mimeType }
    public var byteCount: Int64? { storedMedia.byteCount }
    public var downloadedAt: Date { storedMedia.downloadedAt }
    public var lastAccessedAt: Date { storedMedia.lastAccessedAt }
    public var pageURL: URL? { storedMedia.pageURL }
    public var isPersistent: Bool { storedMedia.isPersistent }

    var rawValue: StoredWebMedia { storedMedia }
}

public actor WebMediaCaptureLibrary {
    private let library: WebMediaLibrary

    public init(library: WebMediaLibrary = WebMediaLibrary()) {
        self.library = library
    }

    public func resolve(
        _ candidate: WebMediaCaptureCandidate,
        requestContext: WebMediaCaptureRequestContext = .init()
    ) async throws -> WebMediaCaptureResolvedMedia {
        let resolved = try await library.resolve(
            candidate.rawValue,
            requestContext: requestContext.rawValue
        )
        return .init(resolved)
    }

    public func download(
        _ candidate: WebMediaCaptureCandidate,
        requestContext: WebMediaCaptureRequestContext = .init(),
        storageScope: WebMediaCaptureStorageScope,
        retentionPolicy: WebMediaCaptureRetentionPolicy? = nil,
        onProgress: @escaping @Sendable (WebMediaCaptureDownloadProgress) -> Void = { _ in }
    ) async throws -> WebMediaCaptureStoredMedia {
        let stored = try await library.download(
            candidate.rawValue,
            requestContext: requestContext.rawValue,
            storageScope: storageScope.rawValueCore,
            retentionPolicy: retentionPolicy?.rawValueCore,
            onProgress: { onProgress(.init($0)) }
        )
        return .init(stored)
    }

    public func storedMedia(for candidate: WebMediaCaptureCandidate) async throws -> WebMediaCaptureStoredMedia? {
        let stored = try await library.storedMedia(for: candidate.rawValue)
        return stored.map(WebMediaCaptureStoredMedia.init)
    }

    public func allStoredMedia(scope: WebMediaCaptureStorageScope? = nil) async throws -> [WebMediaCaptureStoredMedia] {
        let items = try await library.allStoredMedia(scope: scope?.rawValueCore)
        return items.map(WebMediaCaptureStoredMedia.init)
    }

    public func updateStorageScope(
        _ storageScope: WebMediaCaptureStorageScope,
        for id: String
    ) async throws -> WebMediaCaptureStoredMedia {
        let stored = try await library.updateStorageScope(storageScope.rawValueCore, for: id)
        return .init(stored)
    }

    public func deleteStoredMedia(id: String) async throws {
        try await library.deleteStoredMedia(id: id)
    }

    public func deleteAllStoredMedia(scope: WebMediaCaptureStorageScope? = nil) async throws {
        try await library.deleteAllStoredMedia(scope: scope?.rawValueCore)
    }

    public func ensureThumbnail(id: String) async throws -> WebMediaCaptureStoredMedia? {
        let stored = try await library.ensureThumbnail(id: id)
        return stored.map(WebMediaCaptureStoredMedia.init)
    }

    public func touchStoredMedia(id: String) async throws -> WebMediaCaptureStoredMedia? {
        let stored = try await library.touchStoredMedia(id: id)
        return stored.map(WebMediaCaptureStoredMedia.init)
    }

    public func enforceTransientStoragePolicy(exceptPageURLs pageURLs: [URL]) async throws {
        try await library.enforceTransientStoragePolicy(exceptPageURLs: pageURLs)
    }
}

public struct WebMediaCaptureDownloadedMedia: Sendable {
    public let fileURL: URL
    public let response: URLResponse
}

public enum WebMediaCaptureDownloader {
    public static func makeRequest(for media: WebMediaCaptureResolvedMedia) -> URLRequest {
        var request = URLRequest(url: media.url)
        for (name, value) in media.requestHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    public static func download(
        _ media: WebMediaCaptureResolvedMedia,
        using session: URLSession = .shared,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) async throws -> WebMediaCaptureDownloadedMedia {
        let request = makeRequest(for: media)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw WebMediaOfflineStoreError.invalidHTTPStatus(http.statusCode)
        }
        let fileURL = temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(media.url.pathExtension.isEmpty ? "bin" : media.url.pathExtension)
        try data.write(to: fileURL, options: .atomic)
        return WebMediaCaptureDownloadedMedia(fileURL: fileURL, response: response)
    }
}
