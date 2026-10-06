import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WebMediaOfflineStoreTesting {
    @TaskLocal static var downloadWaiterDidRegister: (@Sendable () -> Void)? = nil
    @TaskLocal static var beforeThumbnailPublication: (@Sendable () async -> Void)? = nil
}

public enum WebMediaOfflineStorageScope: String, Codable, CaseIterable, Sendable {
    case transient
    case persistent
}

public enum WebMediaRetentionPolicy: String, Codable, CaseIterable, Sendable {
    case persistent
    case manualTransient
    case untilPageChange
    case untilSessionEnds

    public static func `default`(for storageScope: WebMediaOfflineStorageScope) -> Self {
        switch storageScope {
        case .persistent:
            return .persistent
        case .transient:
            return .manualTransient
        }
    }
}

public enum WebMediaDownloadState: String, Codable, CaseIterable, Sendable {
    case queued
    case downloading
    case downloaded
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .downloaded, .failed, .cancelled:
            return true
        case .queued, .downloading:
            return false
        }
    }
}

public enum StoredWebMediaState: String, Codable, CaseIterable, Sendable {
    case queuedTransient
    case queuedPersistent
    case downloadingTransient
    case downloadingPersistent
    case storedTransient
    case storedPersistent
    case failedTransient
    case failedPersistent
    case cancelledTransient
    case cancelledPersistent

    static func make(
        downloadState: WebMediaDownloadState,
        storageScope: WebMediaOfflineStorageScope
    ) -> Self {
        switch (downloadState, storageScope) {
        case (.queued, .transient):
            return .queuedTransient
        case (.queued, .persistent):
            return .queuedPersistent
        case (.downloading, .transient):
            return .downloadingTransient
        case (.downloading, .persistent):
            return .downloadingPersistent
        case (.downloaded, .transient):
            return .storedTransient
        case (.downloaded, .persistent):
            return .storedPersistent
        case (.failed, .transient):
            return .failedTransient
        case (.failed, .persistent):
            return .failedPersistent
        case (.cancelled, .transient):
            return .cancelledTransient
        case (.cancelled, .persistent):
            return .cancelledPersistent
        }
    }
}

public struct WebMediaDownloadProgress: Codable, Hashable, Sendable {
    public let id: String
    public let fractionCompleted: Double
    public let bytesDownloaded: Int64
    public let totalBytesExpected: Int64?

    public init(
        id: String,
        fractionCompleted: Double,
        bytesDownloaded: Int64,
        totalBytesExpected: Int64?
    ) {
        self.id = id
        self.fractionCompleted = fractionCompleted
        self.bytesDownloaded = bytesDownloaded
        self.totalBytesExpected = totalBytesExpected
    }
}

public enum WebMediaDownloadEventKind: String, Hashable, Sendable {
    case queued
    case restoring
    case downloading
    case progress
    case retried
    case completed
    case failed
    case cancelled
    case deleted
    case scopeUpdated
    case retentionUpdated
    case thumbnailAvailable
}

public struct WebMediaDownloadEvent: Hashable, Sendable {
    public let id: String
    public let kind: WebMediaDownloadEventKind
    public let record: WebMediaDownloadRecord?
    public let storedMedia: StoredWebMedia?

    public init(
        id: String,
        kind: WebMediaDownloadEventKind,
        record: WebMediaDownloadRecord? = nil,
        storedMedia: StoredWebMedia? = nil
    ) {
        self.id = id
        self.kind = kind
        self.record = record
        self.storedMedia = storedMedia
    }
}

public enum WebMediaThumbnailLoadingPolicy: String, Codable, CaseIterable, Sendable {
    case eager
    case lazy
    case none
}

public struct WebMediaThumbnailRequest: Codable, Hashable, Sendable {
    public let loadingPolicy: WebMediaThumbnailLoadingPolicy
    public let generateFromMedia: Bool
    public let preferredFrameTime: TimeInterval
    public let remoteImageURL: URL?
    public let remoteRequestHeaders: [String: String]
    public let imageData: Data?
    public let fileExtension: String?

    public init(
        loadingPolicy: WebMediaThumbnailLoadingPolicy = .eager,
        generateFromMedia: Bool = true,
        preferredFrameTime: TimeInterval = 3,
        remoteImageURL: URL? = nil,
        remoteRequestHeaders: [String: String] = [:],
        imageData: Data? = nil,
        fileExtension: String? = nil
    ) {
        self.loadingPolicy = loadingPolicy
        self.generateFromMedia = generateFromMedia
        self.preferredFrameTime = preferredFrameTime
        self.remoteImageURL = remoteImageURL
        self.remoteRequestHeaders = remoteRequestHeaders
        self.imageData = imageData
        self.fileExtension = fileExtension
    }

    public static var none: Self {
        Self(loadingPolicy: .none, generateFromMedia: false)
    }

    public static func automatic(
        remoteImageURL: URL? = nil,
        remoteRequestHeaders: [String: String] = [:],
        preferredFrameTime: TimeInterval = 3
    ) -> Self {
        Self(
            loadingPolicy: remoteImageURL == nil ? .eager : .lazy,
            generateFromMedia: true,
            preferredFrameTime: preferredFrameTime,
            remoteImageURL: remoteImageURL,
            remoteRequestHeaders: remoteRequestHeaders
        )
    }

    public static func lazy(
        remoteImageURL: URL? = nil,
        remoteRequestHeaders: [String: String] = [:],
        preferredFrameTime: TimeInterval = 3
    ) -> Self {
        Self(
            loadingPolicy: .lazy,
            generateFromMedia: true,
            preferredFrameTime: preferredFrameTime,
            remoteImageURL: remoteImageURL,
            remoteRequestHeaders: remoteRequestHeaders
        )
    }

    public static func inlineImageData(
        _ data: Data,
        fileExtension: String? = nil
    ) -> Self {
        Self(
            loadingPolicy: .eager,
            generateFromMedia: false,
            imageData: data,
            fileExtension: fileExtension
        )
    }

    private enum CodingKeys: String, CodingKey {
        case loadingPolicy
        case generateFromMedia
        case preferredFrameTime
        case remoteImageURL
        case remoteRequestHeaders
        case imageData
        case fileExtension
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.loadingPolicy =
            try container.decodeIfPresent(WebMediaThumbnailLoadingPolicy.self, forKey: .loadingPolicy)
            ?? .eager
        self.generateFromMedia =
            try container.decodeIfPresent(Bool.self, forKey: .generateFromMedia) ?? true
        self.preferredFrameTime =
            try container.decodeIfPresent(TimeInterval.self, forKey: .preferredFrameTime) ?? 3
        self.remoteImageURL = try container.decodeIfPresent(URL.self, forKey: .remoteImageURL)
        self.remoteRequestHeaders =
            try container.decodeIfPresent([String: String].self, forKey: .remoteRequestHeaders) ?? [:]
        self.imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        self.fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
    }
}

public struct ResolvedWebMediaSnapshot: Codable, Hashable, Sendable {
    public let mediaInfo: WebMediaInfo
    public let resolvedMediaURL: URL
    public let mimeType: String?
    public let requestHeaders: [String: String]
    public let resolutionMethod: WebMediaResolutionMethod

    public init(media: ResolvedWebMedia) {
        self.mediaInfo = media.mediaInfo
        self.resolvedMediaURL = media.url
        self.mimeType = media.mimeType
        self.requestHeaders = media.requestHeaders
        self.resolutionMethod = media.resolutionMethod
    }

    public init(
        mediaInfo: WebMediaInfo,
        resolvedMediaURL: URL,
        mimeType: String?,
        requestHeaders: [String: String],
        resolutionMethod: WebMediaResolutionMethod
    ) {
        self.mediaInfo = mediaInfo
        self.resolvedMediaURL = resolvedMediaURL
        self.mimeType = mimeType
        self.requestHeaders = requestHeaders
        self.resolutionMethod = resolutionMethod
    }

    public func makeResolvedMedia() -> ResolvedWebMedia {
        ResolvedWebMedia(
            mediaInfo: mediaInfo,
            url: resolvedMediaURL,
            mimeType: mimeType,
            requestHeaders: requestHeaders,
            resolutionMethod: resolutionMethod
        )
    }

    private enum CodingKeys: String, CodingKey {
        case mediaInfo
        case legacyPlaylistInfo = "playlistInfo"
        case resolvedMediaURL
        case mimeType
        case requestHeaders
        case resolutionMethod
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mediaInfo = try container.decodeIfPresent(WebMediaInfo.self, forKey: .mediaInfo)
            ?? container.decode(WebMediaInfo.self, forKey: .legacyPlaylistInfo)
        self.resolvedMediaURL = try container.decode(URL.self, forKey: .resolvedMediaURL)
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.requestHeaders = try container.decodeIfPresent([String: String].self, forKey: .requestHeaders) ?? [:]
        self.resolutionMethod = try container.decode(WebMediaResolutionMethod.self, forKey: .resolutionMethod)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mediaInfo, forKey: .mediaInfo)
        try container.encode(resolvedMediaURL, forKey: .resolvedMediaURL)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encode(requestHeaders, forKey: .requestHeaders)
        try container.encode(resolutionMethod, forKey: .resolutionMethod)
    }
}

public struct StoredWebMedia: Hashable, Identifiable, Sendable {
    public let id: String
    public let mediaInfo: WebMediaInfo
    public let storedMediaState: StoredWebMediaState
    public let storageScope: WebMediaOfflineStorageScope
    public let retentionPolicy: WebMediaRetentionPolicy
    public let resolvedMediaURL: URL
    public let localMediaURL: URL
    public let localThumbnailURL: URL?
    public let mimeType: String?
    public let byteCount: Int64?
    public let resolutionMethod: WebMediaResolutionMethod
    public let downloadedAt: Date
    public let lastAccessedAt: Date

    public var pageURL: URL? {
        mediaInfo.pageURL
    }

    public var pageLookupKey: String {
        mediaInfo.pageLookupKey
    }

    public var candidateLookupKey: String {
        mediaInfo.candidateLookupKey
    }

    public var isPersistent: Bool {
        storageScope == .persistent
    }
}

public struct WebMediaDownloadRecord: Hashable, Identifiable, Sendable {
    public let id: String
    public let mediaInfo: WebMediaInfo
    public let storedMediaState: StoredWebMediaState
    public let storageScope: WebMediaOfflineStorageScope
    public let retentionPolicy: WebMediaRetentionPolicy
    public let state: WebMediaDownloadState
    public let resolvedMediaURL: URL
    public let localMediaURL: URL?
    public let localThumbnailURL: URL?
    public let mimeType: String?
    public let byteCount: Int64?
    public let resolutionMethod: WebMediaResolutionMethod
    public let progress: WebMediaDownloadProgress?
    public let failureDescription: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let downloadedAt: Date?

    public var pageLookupKey: String {
        mediaInfo.pageLookupKey
    }

    public var candidateLookupKey: String {
        mediaInfo.candidateLookupKey
    }

    public var isPersistent: Bool {
        storageScope == .persistent
    }
}

public enum WebMediaOfflineStoreError: Error, Equatable {
    case mediaNotFound
    case invalidResponse
    case invalidHTTPStatus(Int)
    case downloadFailed
    case downloadNotFinished
    case downloadCancelled
    case thumbnailGenerationFailed
    case downloadInProgress
    case storageTransitionConflict
}

public protocol WebMediaArtifactDownloading: AnyObject, Sendable {
    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact
}

public struct DownloadedWebMediaArtifact: Hashable, Sendable {
    public let relativeMediaPath: String
    public let mimeType: String?
    public let byteCount: Int64?

    public init(relativeMediaPath: String, mimeType: String?, byteCount: Int64?) {
        self.relativeMediaPath = relativeMediaPath
        self.mimeType = mimeType
        self.byteCount = byteCount
    }
}

public final class WebMediaAssetDownloader: WebMediaArtifactDownloading, @unchecked Sendable {
    private let urlSession: URLSession
    private let hlsDownloaderFactory: () -> WebMediaHLSAssetDownloading
    fileprivate static let partialMediaFilename = "media.partial"
    fileprivate static let partialIdentityFilename = "media.partial.identity.json"

    private struct PartialIdentity: Codable {
        let requestKey: String
        let responseURL: String
        let etag: String
        let totalLength: Int64?
    }

    private static func strongETag(_ value: String?) -> String? {
        guard let value, value.count >= 2, value.first == "\"", value.last == "\"",
              !value.contains("\r"), !value.contains("\n") else { return nil }
        return value
    }

    private static func completeTailRange(_ value: String?, knownTotal: Int64?) -> (start: Int64, total: Int64)? {
        guard let value, value.hasPrefix("bytes ") else { return nil }
        let parts = value.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let total = (parts[1] == "*" ? knownTotal : Int64(parts[1])), total > 0 else { return nil }
        let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]),
              start >= 0, start <= end, end == total - 1 else { return nil }
        return (start, total)
    }

    public init(
        urlSession: URLSession = .shared,
        hlsDownloaderFactory: @escaping () -> WebMediaHLSAssetDownloading = { WebMediaHLSAssetDownloader() }
    ) {
        self.urlSession = urlSession
        self.hlsDownloaderFactory = hlsDownloaderFactory
    }

    public func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        if media.mediaInfo.containerKind == .hls {
            return try await hlsDownloaderFactory().download(
                media: media,
                into: directory,
                identifier: identifier,
                onProgress: onProgress
            )
        }

        return try await downloadFile(
            media: media,
            into: directory,
            identifier: identifier,
            onProgress: onProgress
        )
    }

    private func downloadFile(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        var request = URLRequest(
            url: media.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        request.httpMethod = "GET"
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Playback-Session-Id")
        for (header, value) in media.requestHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        // Partial bytes are reusable only with a strong representation validator.
        // Legacy/unvalidated partial files are restarted rather than spliced.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(nil, forHTTPHeaderField: "Range")
        request.setValue(nil, forHTTPHeaderField: "If-Range")
        let temporaryURL = directory.appendingPathComponent(Self.partialMediaFilename)
        let identityURL = directory.appendingPathComponent(Self.partialIdentityFilename)
        let headerEncoder = JSONEncoder()
        headerEncoder.outputFormatting = .sortedKeys
        let headerData = try headerEncoder.encode(media.requestHeaders)
        let requestKey = SHA256.hash(data: Data(media.url.absoluteString.utf8) + headerData)
            .map { String(format: "%02x", $0) }.joined()
        let savedIdentity = (try? Data(contentsOf: identityURL))
            .flatMap { try? JSONDecoder().decode(PartialIdentity.self, from: $0) }
        var existingByteCount = Self.fileSize(at: temporaryURL) ?? 0
        let canResume = existingByteCount > 0
            && savedIdentity?.requestKey == requestKey
            && savedIdentity.map { Self.strongETag($0.etag) != nil
                && $0.totalLength.map { existingByteCount < $0 } != false } == true
        if canResume, let savedIdentity {
            request.setValue("bytes=\(existingByteCount)-", forHTTPHeaderField: "Range")
            request.setValue(savedIdentity.etag, forHTTPHeaderField: "If-Range")
        } else {
            existingByteCount = 0
        }

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WebMediaOfflineStoreError.invalidResponse
        }
        guard response.statusCode == 200 || response.statusCode == 206 else {
            if response.statusCode == 416 {
                // A next explicit retry must start fresh; 416 is not proof of completion.
                try? FileManager.default.removeItem(at: identityURL)
            }
            throw WebMediaOfflineStoreError.invalidHTTPStatus(response.statusCode)
        }
        let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard encoding == nil || encoding == "identity" else {
            throw WebMediaOfflineStoreError.invalidResponse
        }
        let shouldAppend = canResume && response.statusCode == 206
        let expectedContentLength: Int64?
        if response.statusCode == 206 {
            guard shouldAppend, let savedIdentity,
                  Self.strongETag(response.value(forHTTPHeaderField: "ETag")) == savedIdentity.etag,
                  response.url?.absoluteString == savedIdentity.responseURL,
                  let range = Self.completeTailRange(response.value(forHTTPHeaderField: "Content-Range"), knownTotal: savedIdentity.totalLength),
                  range.start == existingByteCount,
                  savedIdentity.totalLength == nil || savedIdentity.totalLength == range.total,
                  response.expectedContentLength < 0
                    || response.expectedContentLength == range.total - range.start
            else {
                // Never append an unverifiable tail. Preserve bytes, invalidate
                // only their resume identity, and let the next retry request 200.
                try? FileManager.default.removeItem(at: identityURL)
                throw WebMediaOfflineStoreError.invalidResponse
            }
            expectedContentLength = range.total
        } else {
            expectedContentLength = response.expectedContentLength >= 0 ? response.expectedContentLength : nil
        }

        if !shouldAppend {
            // Invalidate identity before truncation, so an interrupted restart
            // cannot pair an old prefix with newly written validator metadata.
            if FileManager.default.fileExists(atPath: identityURL.path) {
                try FileManager.default.removeItem(at: identityURL)
            }
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
        }
        if !FileManager.default.fileExists(atPath: temporaryURL.path) {
            guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
                throw WebMediaOfflineStoreError.downloadFailed
            }
        }
        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        defer { try? fileHandle.close() }
        if shouldAppend {
            try fileHandle.seekToEnd()
        } else {
            try fileHandle.truncate(atOffset: 0)
        }
        if let etag = Self.strongETag(response.value(forHTTPHeaderField: "ETag")),
           let responseURL = response.url {
            let identity = PartialIdentity(requestKey: requestKey, responseURL: responseURL.absoluteString,
                                           etag: etag, totalLength: expectedContentLength)
            try JSONEncoder().encode(identity).write(to: identityURL, options: .atomic)
        }
        let responseMimeType = response.value(forHTTPHeaderField: "Content-Type")

        var buffer = Data()
        var sniffData = Data()
        if shouldAppend {
            let reader = try FileHandle(forReadingFrom: temporaryURL)
            defer { try? reader.close() }
            sniffData = try reader.read(upToCount: 4096) ?? Data()
        }
        var totalBytesWritten: Int64 = shouldAppend ? existingByteCount : 0
        let flushThreshold = 64 * 1024
        let sniffThreshold = 4096

        if shouldAppend, existingByteCount > 0 {
            onProgress(
                WebMediaDownloadProgress(
                    id: identifier,
                    fractionCompleted: Self.progress(
                        bytesDownloaded: existingByteCount,
                        totalBytesExpected: expectedContentLength
                    ),
                    bytesDownloaded: existingByteCount,
                    totalBytesExpected: expectedContentLength
                )
            )
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            guard totalBytesWritten < Int64.max,
                  expectedContentLength.map({ totalBytesWritten < $0 }) != false else {
                try fileHandle.truncate(atOffset: UInt64(shouldAppend ? existingByteCount : 0))
                try? FileManager.default.removeItem(at: identityURL)
                throw WebMediaOfflineStoreError.invalidResponse
            }
            buffer.append(byte)
            totalBytesWritten += 1

            if sniffData.count < sniffThreshold {
                sniffData.append(byte)
            }

            if buffer.count >= flushThreshold {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                onProgress(
                    WebMediaDownloadProgress(
                        id: identifier,
                        fractionCompleted: Self.progress(
                            bytesDownloaded: totalBytesWritten,
                            totalBytesExpected: expectedContentLength
                        ),
                        bytesDownloaded: totalBytesWritten,
                        totalBytesExpected: expectedContentLength
                    )
                )
            }
        }

        if buffer.isEmpty == false {
            try fileHandle.write(contentsOf: buffer)
        }

        try Task.checkCancellation()
        guard expectedContentLength.map({ totalBytesWritten == $0 }) != false else {
            if shouldAppend {
                try fileHandle.truncate(atOffset: UInt64(existingByteCount))
                throw WebMediaOfflineStoreError.invalidResponse
            }
            throw WebMediaOfflineStoreError.downloadNotFinished
        }
        try fileHandle.synchronize()
        try fileHandle.close()

        let fileExtension = WebMediaMimeTypeDetector.preferredFileExtension(
            url: media.url,
            mimeType: responseMimeType ?? media.mimeType,
            leadingData: sniffData,
            fallback: "mp4"
        )

        let finalRelativePath = "media.\(fileExtension)"
        let finalURL = directory.appendingPathComponent(finalRelativePath, isDirectory: false)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        try? FileManager.default.removeItem(at: identityURL)

        onProgress(
            WebMediaDownloadProgress(
                id: identifier,
                fractionCompleted: 1,
                bytesDownloaded: totalBytesWritten,
                totalBytesExpected: expectedContentLength ?? totalBytesWritten
            )
        )

        return DownloadedWebMediaArtifact(
            relativeMediaPath: finalRelativePath,
            mimeType: responseMimeType ?? media.mimeType,
            byteCount: totalBytesWritten
        )
    }

    private static func progress(bytesDownloaded: Int64, totalBytesExpected: Int64?) -> Double {
        guard let totalBytesExpected, totalBytesExpected > 0 else {
            return 0
        }
        return min(1, Double(bytesDownloaded) / Double(totalBytesExpected))
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }
}

public protocol WebMediaHLSAssetDownloading: AnyObject, Sendable {
    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact
}

public final class WebMediaHLSAssetDownloader: NSObject, WebMediaHLSAssetDownloading, @unchecked Sendable {
    public func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        // Each invocation owns its cancellation latch, session and continuation.
        // Reusing the public downloader cannot let an old callback finish a new task.
        let operation = WebMediaHLSDownloadOperation()
        return try await operation.download(
            media: media, into: directory, identifier: identifier, onProgress: onProgress
        )
    }
}

private final class WebMediaHLSDownloadOperation: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    // All mutable state and filesystem completion run on this queue. Delegate
    // delivery and cancellation enter through it, including pre-registration cancellation.
    private let stateQueue = DispatchQueue(label: "com.lakeoffire.webmedia.hls-operation")
    private var cancelled = false
    private var finished = false
    private var continuation: CheckedContinuation<DownloadedWebMediaArtifact, Error>?
    private var onProgress: (@Sendable (WebMediaDownloadProgress) -> Void)?
    private var identifier = ""
    private var destinationDirectory = URL(fileURLWithPath: "/")
    private var temporaryLocation: URL?
    private var resolvedMimeType: String?
    private var session: AVAssetDownloadURLSession?
    private var downloadTask: AVAssetDownloadTask?

    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                stateQueue.async {
                    self.continuation = continuation
                    guard !self.cancelled else {
                        self.finish(with: .failure(CancellationError()))
                        return
                    }
                    self.onProgress = onProgress
                    self.identifier = identifier
                    self.destinationDirectory = directory
                    self.resolvedMimeType = media.mimeType
                    let configuration = URLSessionConfiguration.background(
                        withIdentifier: "com.lakeoffire.swift-brave.webmedia.hls.\(UUID().uuidString)"
                    )
                    let session = AVAssetDownloadURLSession(
                        configuration: configuration,
                        assetDownloadDelegate: self,
                        delegateQueue: nil
                    )
                    self.session = session
                    let assetOptions = media.requestHeaders.isEmpty
                        ? nil : ["AVURLAssetHTTPHeaderFieldsKey": media.requestHeaders]
                    let asset = AVURLAsset(url: media.url, options: assetOptions)
                    guard let task = session.makeAssetDownloadTask(
                        asset: asset, assetTitle: media.mediaInfo.preferredDisplayName,
                        assetArtworkData: nil, options: nil
                    ) else {
                        self.finish(with: .failure(WebMediaOfflineStoreError.downloadFailed))
                        return
                    }
                    self.downloadTask = task
                    task.resume()
                }
            }
        } onCancel: {
            self.stateQueue.async {
                guard !self.finished else { return }
                self.cancelled = true
                self.downloadTask?.cancel()
                // If registration has not run, leave the latch for it to consume.
                if self.continuation != nil {
                    self.finish(with: .failure(CancellationError()))
                }
            }
        }
    }

    private func owns(_ session: URLSession, _ task: URLSessionTask) -> Bool {
        !finished && self.session === session && downloadTask === task
    }

    private func finish(with result: Result<DownloadedWebMediaArtifact, Error>) {
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        let session = self.session
        self.session = nil
        downloadTask = nil
        onProgress = nil
        temporaryLocation = nil
        switch result {
        case .success:
            session?.finishTasksAndInvalidate()
        case .failure:
            session?.invalidateAndCancel()
        }
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    willDownloadTo location: URL) {
        stateQueue.async {
            guard self.owns(session, assetDownloadTask) else { return }
            self.temporaryLocation = location
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        // Convert delegate objects to value data before crossing queues.
        let duration = timeRangeExpectedToLoad.duration.seconds
        let loaded = loadedTimeRanges.map(\.timeRangeValue.duration.seconds).reduce(0, +)
        let fraction = duration.isFinite && loaded.isFinite && duration > 0
            ? max(0, min(1, loaded / duration)) : 0
        stateQueue.async {
            guard self.owns(session, assetDownloadTask) else { return }
            self.onProgress?(.init(id: self.identifier, fractionCompleted: fraction,
                                  bytesDownloaded: 0, totalBytesExpected: nil))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            guard self.owns(session, task) else { return }
            if let error {
                self.finish(with: .failure(error))
                return
            }
            guard let temporaryLocation = self.temporaryLocation else {
                self.finish(with: .failure(WebMediaOfflineStoreError.downloadFailed))
                return
            }
            let ext = temporaryLocation.pathExtension.isEmpty ? "movpkg" : temporaryLocation.pathExtension
            let relativePath = "media.\(ext)"
            let finalURL = self.destinationDirectory.appendingPathComponent(relativePath)
            do {
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: temporaryLocation, to: finalURL)
                let byteCount = try StoredWebMediaFileSystem.directorySize(at: finalURL)
                self.onProgress?(.init(id: self.identifier, fractionCompleted: 1,
                                       bytesDownloaded: byteCount, totalBytesExpected: byteCount))
                self.finish(with: .success(.init(relativeMediaPath: relativePath,
                                                mimeType: self.resolvedMimeType, byteCount: byteCount)))
            } catch {
                self.finish(with: .failure(error))
            }
        }
    }
}

public actor WebMediaOfflineStore {
    private struct ActiveDownload: Sendable {
        let attemptID: UUID
        let task: Task<Void, Never>
    }

    private struct EventSubscription: Sendable {
        let idFilter: String?
        let continuation: AsyncStream<WebMediaDownloadEvent>.Continuation
    }

    public struct TransientStoragePolicy: Codable, Hashable, Sendable {
        public var maxItemCount: Int?
        public var maxTotalByteCount: Int64?
        public var maxAge: TimeInterval?

        public init(
            maxItemCount: Int? = 3,
            maxTotalByteCount: Int64? = 2_000_000_000,
            maxAge: TimeInterval? = 7 * 24 * 60 * 60
        ) {
            self.maxItemCount = maxItemCount
            self.maxTotalByteCount = maxTotalByteCount
            self.maxAge = maxAge
        }
    }

    public struct Configuration: Sendable {
        public var persistentRootURL: URL
        public var transientRootURL: URL
        public var excludeFromBackup: Bool
        public var transientStoragePolicy: TransientStoragePolicy

        public init(
            persistentRootURL: URL? = nil,
            transientRootURL: URL? = nil,
            excludeFromBackup: Bool = true,
            transientStoragePolicy: TransientStoragePolicy = .init()
        ) {
            self.persistentRootURL = persistentRootURL ?? Self.migratedDefaultPersistentRootURL()
            self.transientRootURL = transientRootURL ?? Self.migratedDefaultTransientRootURL()
            self.excludeFromBackup = excludeFromBackup
            self.transientStoragePolicy = transientStoragePolicy
        }

        private static func defaultPersistentRootURL() -> URL {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return baseURL
                .appendingPathComponent("WebMedia", isDirectory: true)
                .appendingPathComponent("OfflineMedia", isDirectory: true)
        }

        private static func defaultTransientRootURL() -> URL {
            let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return baseURL
                .appendingPathComponent("WebMedia", isDirectory: true)
                .appendingPathComponent("TransientMedia", isDirectory: true)
        }

        private static func legacyPersistentRootURL() -> URL {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return baseURL
                .appendingPathComponent("BravePlaylist", isDirectory: true)
                .appendingPathComponent("OfflineMedia", isDirectory: true)
        }

        private static func legacyTransientRootURL() -> URL {
            let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return baseURL
                .appendingPathComponent("BravePlaylist", isDirectory: true)
                .appendingPathComponent("TransientMedia", isDirectory: true)
        }

        private static func migratedDefaultPersistentRootURL() -> URL {
            migratedRootURL(
                legacyRootURL: legacyPersistentRootURL(),
                currentRootURL: defaultPersistentRootURL()
            )
        }

        private static func migratedDefaultTransientRootURL() -> URL {
            migratedRootURL(
                legacyRootURL: legacyTransientRootURL(),
                currentRootURL: defaultTransientRootURL()
            )
        }

        private static func migratedRootURL(
            legacyRootURL: URL,
            currentRootURL: URL
        ) -> URL {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: legacyRootURL.path) == false {
                return currentRootURL
            }
            if fileManager.fileExists(atPath: currentRootURL.path) {
                return currentRootURL
            }
            do {
                try fileManager.createDirectory(
                    at: currentRootURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: legacyRootURL, to: currentRootURL)
            } catch {
                do {
                    try fileManager.copyItem(at: legacyRootURL, to: currentRootURL)
                } catch {
                    try? fileManager.createDirectory(
                        at: currentRootURL,
                        withIntermediateDirectories: true
                    )
                }
            }
            return currentRootURL
        }
    }

    public static let shared = WebMediaOfflineStore()

    private let configuration: Configuration
    private let downloader: any WebMediaArtifactDownloading
    private let urlSession: URLSession
    private var activeDownloads: [String: ActiveDownload] = [:]
    private var thumbnailAttempts: [String: UUID] = [:]
    private var downloadWaiters: [String: [UUID: CheckedContinuation<StoredWebMedia, Error>]] = [:]
    private var eventSubscriptions: [UUID: EventSubscription] = [:]

    public init(
        configuration: Configuration = .init(),
        downloader: any WebMediaArtifactDownloading = WebMediaAssetDownloader(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.downloader = downloader
        self.urlSession = urlSession
    }

    public func download(
        _ media: ResolvedWebMedia,
        storageScope: WebMediaOfflineStorageScope,
        retentionPolicy: WebMediaRetentionPolicy? = nil,
        thumbnail: WebMediaThumbnailRequest = .automatic(),
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) async throws -> StoredWebMedia {
        let record = try await enqueueDownload(
            media,
            storageScope: storageScope,
            retentionPolicy: retentionPolicy,
            thumbnail: thumbnail,
            onProgress: onProgress
        )
        if let stored = try storedMedia(id: record.id), record.state == .downloaded {
            return stored
        }
        return try await waitForDownload(id: record.id)
    }

    public func downloadEvents(id: String? = nil) -> AsyncStream<WebMediaDownloadEvent> {
        let subscriptionID = UUID()
        return AsyncStream { continuation in
            eventSubscriptions[subscriptionID] = EventSubscription(
                idFilter: id,
                continuation: continuation
            )
            continuation.onTermination = { _ in
                Task {
                    await self.removeEventSubscription(subscriptionID)
                }
            }
        }
    }

    public func enqueueDownload(
        _ media: ResolvedWebMedia,
        storageScope: WebMediaOfflineStorageScope,
        retentionPolicy: WebMediaRetentionPolicy? = nil,
        thumbnail: WebMediaThumbnailRequest = .automatic(),
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) async throws -> WebMediaDownloadRecord {
        try prepareRootsIfNeeded()

        if let existing = try storedMedia(for: media.mediaInfo) {
            if existing.storageScope == .transient && storageScope == .persistent {
                let promoted = try updateStorageScope(.persistent, for: existing.id)
                return try currentDownloadRecord(id: promoted.id) ?? Self.makeDownloadRecord(from: promoted)
            }
            return Self.makeDownloadRecord(from: existing)
        }

        let existingRecord = try downloadRecord(for: media.mediaInfo)
        let identifier = existingRecord?.id ?? Self.storedMediaIdentifier(for: media.mediaInfo)
        let itemDirectory = directoryURL(for: identifier, scope: storageScope)
        let shouldRestart = existingRecord?.state == .failed || existingRecord?.state == .cancelled

        if let existingRecord, shouldRestart == false {
            if activeDownloads[identifier] == nil,
               existingRecord.state == .queued || existingRecord.state == .downloading {
                startDownload(identifier: identifier, onProgress: onProgress)
            }
            return existingRecord
        }

        let now = Date()
        let resolvedRetentionPolicy = retentionPolicy ?? .default(for: storageScope)
        let metadata: StoredWebMediaMetadata
        if shouldRestart, var existingMetadata = try loadMetadata(id: identifier) {
            let currentDirectory = directoryURL(for: identifier, scope: existingMetadata.storageScope)
            try preserveDownloadPartial(in: currentDirectory, metadata: &existingMetadata)
            existingMetadata = try transitionStorage(
                existingMetadata, to: storageScope, retentionPolicy: resolvedRetentionPolicy
            )
            let targetDirectory = directoryURL(for: identifier, scope: storageScope)
            existingMetadata.mediaInfo = media.mediaInfo
            existingMetadata.storageScope = storageScope
            existingMetadata.retentionPolicy = resolvedRetentionPolicy
            existingMetadata.resolvedMedia = .init(media: media)
            existingMetadata.state = .queued
            existingMetadata.updatedAt = now
            existingMetadata.downloadedAt = nil
            existingMetadata.lastAccessedAt = nil
            existingMetadata.failureDescription = nil
            existingMetadata.mediaRelativePath = nil
            existingMetadata.thumbnailRelativePath = nil
            existingMetadata.byteCount = nil
            existingMetadata.thumbnailRequest = thumbnail
            metadata = existingMetadata
            try writeMetadata(metadata, in: targetDirectory)
        } else {
            if FileManager.default.fileExists(atPath: itemDirectory.path) {
                try FileManager.default.removeItem(at: itemDirectory)
            }
            try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
            metadata = StoredWebMediaMetadata(
                id: identifier,
                mediaInfo: media.mediaInfo,
                storageScope: storageScope,
                retentionPolicy: resolvedRetentionPolicy,
                resolvedMedia: .init(media: media),
                state: .queued,
                createdAt: existingRecord?.createdAt ?? now,
                updatedAt: now,
                downloadedAt: nil,
                lastAccessedAt: nil,
                progress: .init(id: identifier, fractionCompleted: 0, bytesDownloaded: 0, totalBytesExpected: nil),
                failureDescription: nil,
                mediaRelativePath: nil,
                thumbnailRelativePath: nil,
                byteCount: nil,
                thumbnailRequest: thumbnail
            )
            try writeMetadata(metadata, in: itemDirectory)
        }
        emit(
            WebMediaDownloadEvent(
                id: identifier,
                kind: .queued,
                record: metadata.makeDownloadRecord(
                    rootDirectory: directoryURL(for: identifier, scope: metadata.storageScope)
                )
            )
        )
        startDownload(identifier: identifier, onProgress: onProgress)
        return metadata.makeDownloadRecord(
            rootDirectory: directoryURL(for: identifier, scope: metadata.storageScope)
        )
    }

    public func waitForDownload(id: String) async throws -> StoredWebMedia {
        try Task.checkCancellation()
        if let stored = try storedMedia(id: id) {
            return stored
        }

        if let record = try currentDownloadRecord(id: id) {
            switch record.state {
            case .failed:
                throw WebMediaOfflineStoreError.downloadFailed
            case .cancelled:
                throw WebMediaOfflineStoreError.downloadCancelled
            case .queued, .downloading:
                break
            case .downloaded:
                if let stored = try storedMedia(id: id) {
                    return stored
                }
                throw WebMediaOfflineStoreError.downloadNotFinished
            }
        } else {
            throw WebMediaOfflineStoreError.mediaNotFound
        }

        if activeDownloads[id] == nil {
            startDownload(identifier: id)
        }

        let waiterID = UUID()
        let result: StoredWebMedia = try await withTaskCancellationHandler(
            operation: {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    guard Task.isCancelled == false else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    downloadWaiters[id, default: [:]][waiterID] = continuation
                    WebMediaOfflineStoreTesting.downloadWaiterDidRegister?()
                }
            },
            onCancel: {
                Task {
                    await self.cancelDownloadWaiter(id: id, waiterID: waiterID)
                }
            }
        )
        try Task.checkCancellation()
        return result
    }

    public func restorePendingDownloads(
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) async throws -> [WebMediaDownloadRecord] {
        try prepareRootsIfNeeded()
        let records = try allDownloadRecords(states: [.queued, .downloading])
        for record in records where activeDownloads[record.id] == nil {
            emit(WebMediaDownloadEvent(id: record.id, kind: .restoring, record: record))
            startDownload(identifier: record.id, onProgress: onProgress)
        }
        return records
    }

    public func isDownloading(id: String) throws -> Bool {
        if activeDownloads[id] != nil {
            return true
        }
        guard let record = try currentDownloadRecord(id: id) else {
            return false
        }
        return record.state == .queued || record.state == .downloading
    }

    public func cancelDownload(id: String) async throws -> WebMediaDownloadRecord? {
        guard let metadata = try loadMetadata(id: id) else {
            return nil
        }

        if let activeDownload = activeDownloads[id] {
            activeDownload.task.cancel()
            _ = await activeDownload.task.value
        } else if metadata.state == .queued || metadata.state == .downloading {
            markDownloadCancelled(identifier: id)
        }

        return try currentDownloadRecord(id: id)
    }

    public func retryDownload(
        id: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) throws -> WebMediaDownloadRecord {
        try prepareRootsIfNeeded()
        guard var metadata = try loadMetadata(id: id) else {
            throw WebMediaOfflineStoreError.mediaNotFound
        }

        if metadata.state == .downloaded {
            return metadata.makeDownloadRecord(rootDirectory: directoryURL(for: id, scope: metadata.storageScope))
        }

        if activeDownloads[id] != nil {
            throw WebMediaOfflineStoreError.downloadNotFinished
        }

        metadata.state = .queued
        metadata.updatedAt = Date()
        metadata.failureDescription = nil
        let itemDirectory = directoryURL(for: id, scope: metadata.storageScope)
        try writeMetadata(metadata, in: itemDirectory)
        emit(
            WebMediaDownloadEvent(
                id: id,
                kind: .retried,
                record: metadata.makeDownloadRecord(rootDirectory: itemDirectory)
            )
        )
        startDownload(identifier: id, onProgress: onProgress)
        return metadata.makeDownloadRecord(rootDirectory: itemDirectory)
    }

    public func downloadRecord(for item: WebMediaInfo) throws -> WebMediaDownloadRecord? {
        try allDownloadRecords().first(where: { $0.mediaInfo.resourceLookupKey == item.resourceLookupKey })
    }

    public func currentDownloadRecord(id: String) throws -> WebMediaDownloadRecord? {
        guard let metadata = try loadAllMetadata().first(where: { $0.id == id }) else {
            return nil
        }
        return metadata.makeDownloadRecord(
            rootDirectory: directoryURL(for: id, scope: metadata.storageScope)
        )
    }

    public func allDownloadRecords(
        states: Set<WebMediaDownloadState>? = nil
    ) throws -> [WebMediaDownloadRecord] {
        try loadAllMetadata()
            .map { metadata in
                metadata.makeDownloadRecord(rootDirectory: directoryURL(for: metadata.id, scope: metadata.storageScope))
            }
            .filter { states == nil || states?.contains($0.state) == true }
            .sorted(by: Self.preferredDownloadOrdering)
    }

    public func storedMedia(for item: WebMediaInfo) throws -> StoredWebMedia? {
        guard let metadata = try (
            loadAllMetadata()
                .filter { $0.state == .downloaded && $0.mediaInfo.resourceLookupKey == item.resourceLookupKey }
                .sorted(by: Self.preferredStoredMetadataOrdering)
                .first
        )
        else {
            return nil
        }
        return try touchAndMakeStoredMedia(metadata)
    }

    public func storedMedia(forPageURL pageURL: URL) throws -> [StoredWebMedia] {
        let pageLookupKey = WebMediaInfo.pageLookupKey(for: pageURL.absoluteString)
        return try allStoredMedia()
            .filter { $0.pageLookupKey == pageLookupKey }
            .sorted(by: Self.preferredStoredOrdering)
    }

    public func bestStoredMedia(forPageURL pageURL: URL) throws -> StoredWebMedia? {
        guard let metadata = try (
            loadAllMetadata()
                .filter {
                    $0.state == .downloaded
                        && $0.mediaInfo.pageLookupKey == WebMediaInfo.pageLookupKey(for: pageURL.absoluteString)
                }
                .sorted(by: Self.preferredStoredMetadataOrdering)
                .first
        )
        else {
            return nil
        }
        return try touchAndMakeStoredMedia(metadata)
    }

    public func storedMedia(id: String) throws -> StoredWebMedia? {
        guard let metadata = try loadAllMetadata().first(where: { $0.id == id && $0.state == .downloaded }) else {
            return nil
        }
        return try touchAndMakeStoredMedia(metadata)
    }

    public func allStoredMedia(scope: WebMediaOfflineStorageScope? = nil) throws -> [StoredWebMedia] {
        try loadAllMetadata()
            .filter { $0.state == .downloaded && (scope == nil || $0.storageScope == scope) }
            .compactMap { metadata in
                let rootDirectory = directoryURL(for: metadata.id, scope: metadata.storageScope)
                return metadata.makeStoredMedia(rootDirectory: rootDirectory)
            }
            .filter { FileManager.default.fileExists(atPath: $0.localMediaURL.path) }
            .sorted(by: Self.preferredStoredOrdering)
    }

    @discardableResult
    public func updateStorageScope(
        _ storageScope: WebMediaOfflineStorageScope,
        for id: String
    ) throws -> StoredWebMedia {
        try prepareRootsIfNeeded()
        guard var metadata = try loadMetadata(id: id) else {
            throw WebMediaOfflineStoreError.mediaNotFound
        }

        guard metadata.state == .downloaded else {
            throw WebMediaOfflineStoreError.downloadNotFinished
        }
        if metadata.storageScope == storageScope {
            guard let stored = metadata.makeStoredMedia(rootDirectory: directoryURL(for: id, scope: storageScope)) else {
                throw WebMediaOfflineStoreError.mediaNotFound
            }
            return stored
        }

        guard activeDownloads[id] == nil else {
            throw WebMediaOfflineStoreError.downloadInProgress
        }
        let targetPolicy: WebMediaRetentionPolicy = storageScope == .persistent
            ? .persistent
            : (metadata.retentionPolicy == .persistent ? .manualTransient : metadata.retentionPolicy)
        metadata = try transitionStorage(metadata, to: storageScope, retentionPolicy: targetPolicy)
        let destinationDirectory = directoryURL(for: id, scope: storageScope)
        if storageScope == .transient {
            // Storage is committed; cache maintenance cannot roll it back.
            try? enforceTransientStoragePolicy(excluding: [id], exceptPageLookupKeys: [])
        }

        guard let stored = metadata.makeStoredMedia(rootDirectory: destinationDirectory) else {
            throw WebMediaOfflineStoreError.mediaNotFound
        }
        emit(
            WebMediaDownloadEvent(
                id: id,
                kind: .scopeUpdated,
                record: metadata.makeDownloadRecord(rootDirectory: destinationDirectory),
                storedMedia: stored
            )
        )
        return stored
    }

    @discardableResult
    public func updateRetentionPolicy(
        _ retentionPolicy: WebMediaRetentionPolicy,
        for id: String
    ) throws -> WebMediaDownloadRecord {
        try prepareRootsIfNeeded()
        guard var metadata = try loadMetadata(id: id) else {
            throw WebMediaOfflineStoreError.mediaNotFound
        }

        guard metadata.state == .downloaded else {
            throw WebMediaOfflineStoreError.downloadNotFinished
        }
        guard activeDownloads[id] == nil else {
            throw WebMediaOfflineStoreError.downloadInProgress
        }
        let targetScope: WebMediaOfflineStorageScope = retentionPolicy == .persistent ? .persistent : .transient
        metadata = try transitionStorage(metadata, to: targetScope, retentionPolicy: retentionPolicy)
        let itemDirectory = directoryURL(for: id, scope: metadata.storageScope)
        if metadata.storageScope == .transient {
            try? enforceTransientStoragePolicy(excluding: [id], exceptPageLookupKeys: [])
        }
        emit(
            WebMediaDownloadEvent(
                id: id,
                kind: .retentionUpdated,
                record: metadata.makeDownloadRecord(rootDirectory: itemDirectory),
                storedMedia: metadata.makeStoredMedia(rootDirectory: itemDirectory)
            )
        )
        return metadata.makeDownloadRecord(rootDirectory: itemDirectory)
    }

    public func deleteStoredMedia(id: String) throws {
        let existingRecord = try currentDownloadRecord(id: id)
        thumbnailAttempts.removeValue(forKey: id)
        activeDownloads.removeValue(forKey: id)?.task.cancel()
        finishWaiters(id: id, result: .failure(WebMediaOfflineStoreError.downloadCancelled))
        for scope in WebMediaOfflineStorageScope.allCases {
            try deleteDirectoryIfPresent(directoryURL(for: id, scope: scope))
            try deleteDirectoryIfPresent(downloadStagingRoot(for: id, scope: scope))
        }
        emit(WebMediaDownloadEvent(id: id, kind: .deleted, record: existingRecord))
    }

    public func deleteAllStoredMedia(scope: WebMediaOfflineStorageScope? = nil) throws {
        let records = try allDownloadRecords().filter { scope == nil || $0.storageScope == scope }
        let recordIDs = Set(records.map(\.id))
        for record in records {
            thumbnailAttempts.removeValue(forKey: record.id)
            activeDownloads.removeValue(forKey: record.id)?.task.cancel()
            finishWaiters(id: record.id, result: .failure(WebMediaOfflineStoreError.downloadCancelled))
        }
        if scope == nil {
            thumbnailAttempts.removeAll()
            let activeIDs = Array(activeDownloads.keys)
            for id in activeIDs where recordIDs.contains(id) == false {
                activeDownloads.removeValue(forKey: id)?.task.cancel()
                finishWaiters(id: id, result: .failure(WebMediaOfflineStoreError.downloadCancelled))
            }
        }

        let scopes = scope.map { [$0] } ?? WebMediaOfflineStorageScope.allCases
        for targetScope in scopes {
            let rootURL = rootURL(for: targetScope)
            if FileManager.default.fileExists(atPath: rootURL.path) {
                try FileManager.default.removeItem(at: rootURL)
            }
        }
        try prepareRootsIfNeeded()
    }

    public func purgeTransientMedia() throws {
        try deleteAllStoredMedia(scope: .transient)
    }

    public func deleteTransientMedia(forPageURL pageURL: URL) throws {
        let pageLookupKey = WebMediaInfo.pageLookupKey(for: pageURL.absoluteString)
        let transientRecords = try allDownloadRecords()
            .filter { $0.storageScope == .transient && $0.pageLookupKey == pageLookupKey }
        for record in transientRecords {
            try deleteStoredMedia(id: record.id)
        }
    }

    public func purgeTransientMedia(exceptPageURLs pageURLs: [URL]) throws {
        let retainedKeys = Set(pageURLs.map { WebMediaInfo.pageLookupKey(for: $0.absoluteString) })
        let transientRecords = try allDownloadRecords().filter { $0.storageScope == .transient }
        for record in transientRecords where retainedKeys.contains(record.pageLookupKey) == false {
            try deleteStoredMedia(id: record.id)
        }
    }

    public func enforceTransientStoragePolicy(exceptPageURLs pageURLs: [URL]) throws {
        let pageLookupKeys = Set(pageURLs.map { WebMediaInfo.pageLookupKey(for: $0.absoluteString) })
        try enforceTransientStoragePolicy(excluding: [], exceptPageLookupKeys: pageLookupKeys)
    }

    public func handlePageDidChange(from oldPageURL: URL?, to newPageURL: URL?) throws {
        let oldPageKey = oldPageURL.map { WebMediaInfo.pageLookupKey(for: $0.absoluteString) }
        let newPageKey = newPageURL.map { WebMediaInfo.pageLookupKey(for: $0.absoluteString) }
        let transientRecords = try allDownloadRecords().filter {
            $0.storageScope == .transient && $0.retentionPolicy == .untilPageChange
        }

        for record in transientRecords {
            let shouldDelete: Bool
            if let oldPageKey {
                shouldDelete = record.pageLookupKey == oldPageKey && record.pageLookupKey != newPageKey
            } else if let newPageKey {
                shouldDelete = record.pageLookupKey != newPageKey
            } else {
                shouldDelete = true
            }

            if shouldDelete {
                try deleteStoredMedia(id: record.id)
            }
        }
    }

    public func handleSessionDidEnd() throws {
        let transientRecords = try allDownloadRecords().filter {
            $0.storageScope == .transient &&
                ($0.retentionPolicy == .untilPageChange || $0.retentionPolicy == .untilSessionEnds)
        }
        for record in transientRecords {
            try deleteStoredMedia(id: record.id)
        }
    }

    @discardableResult
    public func ensureThumbnail(id: String) async throws -> StoredWebMedia? {
        try Task.checkCancellation()
        guard var metadata = try loadMetadata(id: id) else {
            throw WebMediaOfflineStoreError.mediaNotFound
        }
        guard metadata.state == .downloaded else {
            return nil
        }

        let itemDirectory = directoryURL(for: id, scope: metadata.storageScope)
        if let thumbnailRelativePath = metadata.thumbnailRelativePath {
            let thumbnailURL = itemDirectory.appendingPathComponent(thumbnailRelativePath, isDirectory: false)
            if FileManager.default.fileExists(atPath: thumbnailURL.path),
               let stored = metadata.makeStoredMedia(rootDirectory: itemDirectory) {
                return stored
            }
            metadata.thumbnailRelativePath = nil
        }

        guard metadata.thumbnailRequest.loadingPolicy != .none,
              let mediaRelativePath = metadata.mediaRelativePath
        else {
            return metadata.makeStoredMedia(rootDirectory: itemDirectory)
        }

        let thumbnailAttemptID = UUID()
        thumbnailAttempts[id] = thumbnailAttemptID
        let thumbnailDirectory = thumbnailStagingDirectory(
            attemptID: thumbnailAttemptID
        )
        defer {
            if thumbnailAttempts[id] == thumbnailAttemptID {
                thumbnailAttempts.removeValue(forKey: id)
            }
            try? deleteDirectoryIfPresent(thumbnailDirectory)
        }
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)

        let mediaURL = itemDirectory.appendingPathComponent(mediaRelativePath, isDirectory: false)
        let thumbnailRelativePath = try await storeThumbnail(
            metadata.thumbnailRequest,
            mediaURL: mediaURL,
            directory: thumbnailDirectory,
            shouldMaterializeImmediately: true
        )

        await WebMediaOfflineStoreTesting.beforeThumbnailPublication?()

        try Task.checkCancellation()
        guard thumbnailAttempts[id] == thumbnailAttemptID,
              var currentMetadata = try loadMetadata(id: id),
              currentMetadata.state == .downloaded,
              currentMetadata.mediaInfo.resourceLookupKey == metadata.mediaInfo.resourceLookupKey,
              currentMetadata.mediaRelativePath == mediaRelativePath
        else {
            return nil
        }

        let currentDirectory = directoryURL(for: id, scope: currentMetadata.storageScope)
        if let thumbnailRelativePath {
            try publishArtifact(
                relativePath: thumbnailRelativePath,
                from: thumbnailDirectory,
                to: currentDirectory
            )
        }
        currentMetadata.thumbnailRelativePath = thumbnailRelativePath
        currentMetadata.updatedAt = Date()
        try writeMetadata(currentMetadata, in: currentDirectory)
        emit(
            WebMediaDownloadEvent(
                id: id,
                kind: .thumbnailAvailable,
                record: currentMetadata.makeDownloadRecord(rootDirectory: currentDirectory),
                storedMedia: currentMetadata.makeStoredMedia(rootDirectory: currentDirectory)
            )
        )
        return currentMetadata.makeStoredMedia(rootDirectory: currentDirectory)
    }

    public func enforceTransientStoragePolicy() throws {
        try enforceTransientStoragePolicy(excluding: [], exceptPageLookupKeys: [])
    }

    @discardableResult
    public func touchStoredMedia(id: String) throws -> StoredWebMedia? {
        guard let metadata = try loadAllMetadata().first(where: { $0.id == id && $0.state == .downloaded }) else {
            return nil
        }
        return try touchAndMakeStoredMedia(metadata)
    }

    private func startDownload(
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) {
        guard activeDownloads[identifier] == nil else {
            return
        }

        let attemptID = UUID()
        thumbnailAttempts.removeValue(forKey: identifier)
        let task = Task {
            await self.performDownload(
                identifier: identifier,
                attemptID: attemptID,
                onProgress: onProgress
            )
        }
        activeDownloads[identifier] = ActiveDownload(attemptID: attemptID, task: task)
    }

    private func performDownload(
        identifier: String,
        attemptID: UUID,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async {
        defer {
            removeActiveDownload(identifier: identifier, attemptID: attemptID)
        }

        do {
            guard isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID) else {
                return
            }
            guard var metadata = try loadMetadata(id: identifier) else {
                finishWaiters(id: identifier, result: .failure(WebMediaOfflineStoreError.mediaNotFound))
                return
            }

            let itemDirectory = directoryURL(for: identifier, scope: metadata.storageScope)
            let stagingDirectory = downloadStagingDirectory(
                for: identifier,
                scope: metadata.storageScope,
                attemptID: attemptID
            )
            try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let existingPartialURL = itemDirectory.appendingPathComponent(
                WebMediaAssetDownloader.partialMediaFilename,
                isDirectory: false
            )
            let stagedPartialURL = stagingDirectory.appendingPathComponent(
                WebMediaAssetDownloader.partialMediaFilename,
                isDirectory: false
            )
            let previousStagingDirectory = metadata.downloadAttemptIdentifier.map {
                downloadStagingDirectory(for: identifier, scope: metadata.storageScope, attemptID: $0)
            }
            let interruptedPartialURL = previousStagingDirectory?.appendingPathComponent(
                WebMediaAssetDownloader.partialMediaFilename, isDirectory: false
            )
            let resumePartialURL = interruptedPartialURL.flatMap {
                FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
            } ?? existingPartialURL
            defer {
                // Preserve the current attempt's partial bytes on an orderly
                // failure or cancellation. Deleted/superseded attempts own no files.
                var shouldDeleteStagingDirectory = true
                if isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID),
                   FileManager.default.fileExists(atPath: stagedPartialURL.path) {
                    do {
                        try publishPartial(from: stagingDirectory, to: itemDirectory)
                    } catch {
                        // Keep the durable attempt pointer usable if moving the
                        // partial file fails. Terminal-state publication retries it.
                        shouldDeleteStagingDirectory = false
                    }
                }
                if shouldDeleteStagingDirectory {
                    try? deleteDirectoryIfPresent(stagingDirectory)
                }
            }
            if FileManager.default.fileExists(atPath: resumePartialURL.path) {
                try FileManager.default.copyItem(at: resumePartialURL, to: stagedPartialURL)
                let resumeIdentityURL = resumePartialURL.deletingLastPathComponent()
                    .appendingPathComponent(WebMediaAssetDownloader.partialIdentityFilename)
                if FileManager.default.fileExists(atPath: resumeIdentityURL.path) {
                    try FileManager.default.copyItem(
                        at: resumeIdentityURL,
                        to: stagingDirectory.appendingPathComponent(WebMediaAssetDownloader.partialIdentityFilename)
                    )
                }
            }

            metadata.state = .downloading
            // Persist the working directory's identity before suspending so
            // restorePendingDownloads can resume it after process termination.
            metadata.downloadAttemptIdentifier = attemptID
            metadata.updatedAt = Date()
            metadata.failureDescription = nil
            try writeMetadata(metadata, in: itemDirectory)
            if let previousStagingDirectory { try? deleteDirectoryIfPresent(previousStagingDirectory) }
            emit(
                WebMediaDownloadEvent(
                    id: identifier,
                    kind: .downloading,
                    record: metadata.makeDownloadRecord(rootDirectory: itemDirectory)
                )
            )

            let artifact = try await downloader.download(
                media: metadata.resolvedMedia.makeResolvedMedia(),
                into: stagingDirectory,
                identifier: identifier,
                onProgress: { progress in
                    Task {
                        await self.updateProgress(
                            identifier: identifier,
                            attemptID: attemptID,
                            progress: progress,
                            onProgress: onProgress
                        )
                    }
                }
            )

            try Task.checkCancellation()

            guard isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID),
                  let currentMetadata = try loadMetadata(id: identifier),
                  currentMetadata.state == .downloading
            else {
                return
            }

            metadata = currentMetadata
            let currentItemDirectory = directoryURL(for: identifier, scope: metadata.storageScope)

            let mediaURL = stagingDirectory.appendingPathComponent(artifact.relativeMediaPath, isDirectory: false)
            let thumbnailRelativePath = try await storeThumbnail(
                metadata.thumbnailRequest,
                mediaURL: mediaURL,
                directory: stagingDirectory,
                shouldMaterializeImmediately: metadata.thumbnailRequest.loadingPolicy == .eager
            )

            try Task.checkCancellation()

            metadata.state = .downloaded
            metadata.downloadAttemptIdentifier = nil
            metadata.updatedAt = Date()
            metadata.downloadedAt = Date()
            metadata.lastAccessedAt = metadata.downloadedAt
            metadata.progress = WebMediaDownloadProgress(
                id: identifier,
                fractionCompleted: 1,
                bytesDownloaded: artifact.byteCount ?? 0,
                totalBytesExpected: artifact.byteCount
            )
            metadata.failureDescription = nil
            metadata.byteCount = artifact.byteCount
            metadata.mediaRelativePath = artifact.relativeMediaPath
            metadata.thumbnailRelativePath = thumbnailRelativePath
            metadata.resolvedMedia = ResolvedWebMediaSnapshot(
                mediaInfo: metadata.mediaInfo,
                resolvedMediaURL: metadata.resolvedMedia.resolvedMediaURL,
                mimeType: artifact.mimeType ?? metadata.resolvedMedia.mimeType,
                requestHeaders: metadata.resolvedMedia.requestHeaders,
                resolutionMethod: metadata.resolvedMedia.resolutionMethod
            )
            guard isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID) else {
                return
            }
            try deletePayloadFiles(in: currentItemDirectory)
            try publishArtifact(
                relativePath: artifact.relativeMediaPath,
                from: stagingDirectory,
                to: currentItemDirectory
            )
            if let thumbnailRelativePath {
                try publishArtifact(
                    relativePath: thumbnailRelativePath,
                    from: stagingDirectory,
                    to: currentItemDirectory
                )
            }
            guard let stored = metadata.makeStoredMedia(rootDirectory: currentItemDirectory) else {
                throw WebMediaOfflineStoreError.downloadNotFinished
            }
            try writeMetadata(metadata, in: currentItemDirectory)

            if metadata.storageScope == .transient {
                let pageLookupKeys = Set(
                    metadata.mediaInfo.pageURL.map { WebMediaInfo.pageLookupKey(for: $0.absoluteString) }.map { [$0] }
                        ?? []
                )
                try? enforceTransientStoragePolicy(excluding: [identifier], exceptPageLookupKeys: pageLookupKeys)
            }

            emit(
                WebMediaDownloadEvent(
                    id: identifier,
                    kind: .completed,
                    record: metadata.makeDownloadRecord(rootDirectory: currentItemDirectory),
                    storedMedia: stored
                )
            )

            finishWaiters(id: identifier, result: .success(stored))
        } catch is CancellationError {
            markDownloadCancelled(identifier: identifier, attemptID: attemptID)
        } catch {
            markDownloadFailed(identifier: identifier, attemptID: attemptID, error: error)
        }
    }

    private func updateProgress(
        identifier: String,
        attemptID: UUID,
        progress: WebMediaDownloadProgress,
        onProgress: @Sendable (WebMediaDownloadProgress) -> Void
    ) {
        guard isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID) else {
            return
        }
        guard var metadata = try? loadMetadata(id: identifier) else {
            return
        }

        let itemDirectory = directoryURL(for: identifier, scope: metadata.storageScope)

        metadata.progress = progress
        metadata.updatedAt = Date()
        try? writeMetadata(metadata, in: itemDirectory)
        emit(
            WebMediaDownloadEvent(
                id: identifier,
                kind: .progress,
                record: metadata.makeDownloadRecord(rootDirectory: itemDirectory)
            )
        )
        onProgress(progress)
    }

    private func markDownloadCancelled(identifier: String, attemptID: UUID? = nil) {
        if let attemptID,
           isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID) == false {
            return
        }
        guard var metadata = try? loadMetadata(id: identifier) else {
            finishWaiters(id: identifier, result: .failure(WebMediaOfflineStoreError.downloadCancelled))
            return
        }

        let itemDirectory = directoryURL(for: identifier, scope: metadata.storageScope)
        metadata.state = .cancelled
        try? preserveDownloadPartial(in: itemDirectory, metadata: &metadata)
        metadata.updatedAt = Date()
        metadata.failureDescription = nil
        metadata.mediaRelativePath = nil
        metadata.thumbnailRelativePath = nil
        metadata.byteCount = nil
        try? deleteCompletedArtifacts(in: itemDirectory)
        try? writeMetadata(metadata, in: itemDirectory)
        emit(
            WebMediaDownloadEvent(
                id: identifier,
                kind: .cancelled,
                record: metadata.makeDownloadRecord(rootDirectory: itemDirectory)
            )
        )
        finishWaiters(id: identifier, result: .failure(WebMediaOfflineStoreError.downloadCancelled))
    }

    private func markDownloadFailed(identifier: String, attemptID: UUID, error: Error) {
        guard isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID) else {
            return
        }
        guard var metadata = try? loadMetadata(id: identifier) else {
            finishWaiters(id: identifier, result: .failure(error))
            return
        }

        let itemDirectory = directoryURL(for: identifier, scope: metadata.storageScope)
        metadata.state = .failed
        try? preserveDownloadPartial(in: itemDirectory, metadata: &metadata)
        metadata.updatedAt = Date()
        metadata.failureDescription = error.localizedDescription
        metadata.mediaRelativePath = nil
        metadata.thumbnailRelativePath = nil
        metadata.byteCount = nil
        try? deleteCompletedArtifacts(in: itemDirectory)
        try? writeMetadata(metadata, in: itemDirectory)
        emit(
            WebMediaDownloadEvent(
                id: identifier,
                kind: .failed,
                record: metadata.makeDownloadRecord(rootDirectory: itemDirectory)
            )
        )
        finishWaiters(id: identifier, result: .failure(error))
    }

    private func finishWaiters(
        id: String,
        result: Result<StoredWebMedia, Error>
    ) {
        let waiters = downloadWaiters.removeValue(forKey: id) ?? [:]
        for waiter in waiters.values {
            switch result {
            case .success(let stored):
                waiter.resume(returning: stored)
            case .failure(let error):
                waiter.resume(throwing: error)
            }
        }
    }

    private func cancelDownloadWaiter(id: String, waiterID: UUID) {
        guard let waiter = downloadWaiters[id]?.removeValue(forKey: waiterID) else {
            return
        }
        if downloadWaiters[id]?.isEmpty == true {
            downloadWaiters.removeValue(forKey: id)
        }
        waiter.resume(throwing: CancellationError())
    }

    private func isCurrentDownloadAttempt(identifier: String, attemptID: UUID) -> Bool {
        activeDownloads[identifier]?.attemptID == attemptID
    }

    private func removeActiveDownload(identifier: String, attemptID: UUID) {
        guard isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID) else {
            return
        }
        activeDownloads.removeValue(forKey: identifier)
    }

    private func emit(_ event: WebMediaDownloadEvent) {
        for subscription in eventSubscriptions.values {
            if let idFilter = subscription.idFilter, idFilter != event.id {
                continue
            }
            subscription.continuation.yield(event)
        }
    }

    private func removeEventSubscription(_ subscriptionID: UUID) {
        eventSubscriptions.removeValue(forKey: subscriptionID)
    }

    private func storeThumbnail(
        _ thumbnail: WebMediaThumbnailRequest,
        mediaURL: URL,
        directory: URL,
        shouldMaterializeImmediately: Bool
    ) async throws -> String? {
        guard thumbnail.loadingPolicy != .none, shouldMaterializeImmediately else {
            return nil
        }

        if let imageData = thumbnail.imageData {
            let fileExtension = thumbnail.fileExtension ?? "jpg"
            let relativePath = "thumbnail.\(fileExtension)"
            let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
            try imageData.write(to: destinationURL)
            return relativePath
        }

        if thumbnail.generateFromMedia,
           let relativePath = try StoredWebMediaThumbnailStore.generateMediaThumbnail(
                from: mediaURL,
                preferredFrameTime: thumbnail.preferredFrameTime,
                directory: directory
           ) {
            return relativePath
        }

        if let remoteImageURL = thumbnail.remoteImageURL {
            return try await StoredWebMediaThumbnailStore.storeRemoteThumbnail(
                from: remoteImageURL,
                headers: thumbnail.remoteRequestHeaders,
                directory: directory,
                using: urlSession
            )
        }

        return nil
    }

    private func enforceTransientStoragePolicy(
        excluding excludedIDs: Set<String>,
        exceptPageLookupKeys: Set<String>
    ) throws {
        let policy = configuration.transientStoragePolicy
        guard policy.maxItemCount != nil || policy.maxTotalByteCount != nil || policy.maxAge != nil else {
            return
        }

        let now = Date()
        var records = try allStoredMedia(scope: .transient)
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }

        if let maxAge = policy.maxAge {
            for record in records where now.timeIntervalSince(record.lastAccessedAt) > maxAge {
                if excludedIDs.contains(record.id) == false && exceptPageLookupKeys.contains(record.pageLookupKey) == false {
                    try deleteStoredMedia(id: record.id)
                }
            }
            records = try allStoredMedia(scope: .transient)
                .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        }

        if let maxItemCount = policy.maxItemCount {
            while records.filter({
                excludedIDs.contains($0.id) == false && exceptPageLookupKeys.contains($0.pageLookupKey) == false
            }).count > maxItemCount,
                  let record = records.first(where: {
                      excludedIDs.contains($0.id) == false && exceptPageLookupKeys.contains($0.pageLookupKey) == false
                  }) {
                try deleteStoredMedia(id: record.id)
                records.removeAll(where: { $0.id == record.id })
            }
        }

        if let maxTotalByteCount = policy.maxTotalByteCount {
            var totalBytes = records
                .filter {
                    excludedIDs.contains($0.id) == false && exceptPageLookupKeys.contains($0.pageLookupKey) == false
                }
                .reduce(Int64(0)) { $0 + ($1.byteCount ?? 0) }
            while totalBytes > maxTotalByteCount,
                  let record = records.first(where: {
                      excludedIDs.contains($0.id) == false && exceptPageLookupKeys.contains($0.pageLookupKey) == false
                  }) {
                try deleteStoredMedia(id: record.id)
                records.removeAll(where: { $0.id == record.id })
                totalBytes -= record.byteCount ?? 0
            }
        }
    }

    private func loadMetadata(id: String) throws -> StoredWebMediaMetadata? {
        for scope in WebMediaOfflineStorageScope.allCases {
            let directory = directoryURL(for: id, scope: scope)
            if FileManager.default.fileExists(atPath: directory.path) {
                return try readMetadata(from: directory, storageScope: scope)
            }
        }
        return nil
    }

    private func loadAllMetadata() throws -> [StoredWebMediaMetadata] {
        try prepareRootsIfNeeded()
        var byID: [String: StoredWebMediaMetadata] = [:]
        for scope in WebMediaOfflineStorageScope.allCases {
            for metadata in try loadMetadata(in: rootURL(for: scope), storageScope: scope) {
                byID[metadata.id] = metadata
            }
        }
        return Array(byID.values)
    }

    private func loadMetadata(
        in rootURL: URL,
        storageScope: WebMediaOfflineStorageScope
    ) throws -> [StoredWebMediaMetadata] {
        let directoryURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var result = [StoredWebMediaMetadata]()
        for directoryURL in directoryURLs {
            let resourceValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else {
                continue
            }

            do {
                let metadata = try readMetadata(from: directoryURL, storageScope: storageScope)
                result.append(metadata)
            } catch {
                // Keep uncertain/unreadable data intact; callers can retry.
                throw error
            }
        }
        return result
    }

    private func prepareRootsIfNeeded() throws {
        try [configuration.persistentRootURL, configuration.transientRootURL].forEach { rootURL in
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            if configuration.excludeFromBackup {
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                var mutableRootURL = rootURL
                try mutableRootURL.setResourceValues(resourceValues)
            }
        }
    }

    private func rootURL(for scope: WebMediaOfflineStorageScope) -> URL {
        switch scope {
        case .transient:
            return configuration.transientRootURL
        case .persistent:
            return configuration.persistentRootURL
        }
    }

    private func directoryURL(for identifier: String, scope: WebMediaOfflineStorageScope) -> URL {
        rootURL(for: scope).appendingPathComponent(identifier, isDirectory: true)
    }

    private func downloadStagingDirectory(
        for identifier: String,
        scope: WebMediaOfflineStorageScope,
        attemptID: UUID
    ) -> URL {
        downloadStagingRoot(for: identifier, scope: scope)
            .appendingPathComponent(attemptID.uuidString, isDirectory: true)
    }

    private func downloadStagingRoot(for identifier: String, scope: WebMediaOfflineStorageScope) -> URL {
        rootURL(for: scope)
            .appendingPathComponent(".download-attempts", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
    }

    private func preserveDownloadPartial(
        in itemDirectory: URL,
        metadata: inout StoredWebMediaMetadata
    ) throws {
        guard let attemptID = metadata.downloadAttemptIdentifier else {
            return
        }
        let stagingDirectory = downloadStagingDirectory(
            for: metadata.id, scope: metadata.storageScope, attemptID: attemptID
        )
        let partialURL = stagingDirectory.appendingPathComponent(WebMediaAssetDownloader.partialMediaFilename)
        if FileManager.default.fileExists(atPath: partialURL.path) {
            try publishPartial(from: stagingDirectory, to: itemDirectory)
        }
        // Clear the pointer only after its resumable bytes have a durable home.
        // On failure the terminal record retains it for a later retry.
        metadata.downloadAttemptIdentifier = nil
        try? deleteDirectoryIfPresent(stagingDirectory)
    }

    private func thumbnailStagingDirectory(
        attemptID: UUID
    ) -> URL {
        // A completed item can change retention while its thumbnail is loading.
        // Its working directory must survive deletion of the old storage scope.
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WebMedia-thumbnail-\(attemptID.uuidString)", isDirectory: true)
    }

    private func publishPartial(from stagingDirectory: URL, to itemDirectory: URL) throws {
        let destinationIdentity = itemDirectory.appendingPathComponent(WebMediaAssetDownloader.partialIdentityFilename)
        if FileManager.default.fileExists(atPath: destinationIdentity.path) {
            try FileManager.default.removeItem(at: destinationIdentity)
        }
        try publishArtifact(relativePath: WebMediaAssetDownloader.partialMediaFilename,
                            from: stagingDirectory, to: itemDirectory)
        let sourceIdentity = stagingDirectory.appendingPathComponent(WebMediaAssetDownloader.partialIdentityFilename)
        if FileManager.default.fileExists(atPath: sourceIdentity.path) {
            try publishArtifact(relativePath: WebMediaAssetDownloader.partialIdentityFilename,
                                from: stagingDirectory, to: itemDirectory)
        }
    }

    private func publishArtifact(
        relativePath: String,
        from stagingDirectory: URL,
        to itemDirectory: URL
    ) throws {
        let sourceURL = stagingDirectory.appendingPathComponent(relativePath, isDirectory: false)
        let destinationURL = itemDirectory.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    // Persist the complete requested transition before moving any payload. A
    // restart can finish the same intent from either directory without guessing
    // a retention policy from the directory's name.
    private func transitionStorage(
        _ metadata: StoredWebMediaMetadata,
        to scope: WebMediaOfflineStorageScope,
        retentionPolicy: WebMediaRetentionPolicy
    ) throws -> StoredWebMediaMetadata {
        var pending = metadata
        let source = directoryURL(for: metadata.id, scope: metadata.storageScope)
        pending.pendingStorageTransition = .init(scope: scope, retentionPolicy: retentionPolicy)
        pending.updatedAt = Date()
        try writeMetadata(pending, in: source)
        return try completeStorageTransition(pending, foundIn: source)
    }

    private func completeStorageTransition(
        _ metadata: StoredWebMediaMetadata,
        foundIn directory: URL
    ) throws -> StoredWebMediaMetadata {
        guard let intent = metadata.pendingStorageTransition else { return metadata }
        let destination = directoryURL(for: metadata.id, scope: intent.scope)
        if directory.standardizedFileURL != destination.standardizedFileURL {
            // A second copy is ambiguous. Never delete it to make a move succeed.
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw WebMediaOfflineStoreError.storageTransitionConflict
            }
            try FileManager.default.moveItem(at: directory, to: destination)
        }
        var committed = metadata
        committed.storageScope = intent.scope
        committed.retentionPolicy = intent.retentionPolicy
        committed.pendingStorageTransition = nil
        try writeMetadata(committed, in: destination)
        return committed
    }

    private func readMetadata(
        from directory: URL,
        storageScope: WebMediaOfflineStorageScope
    ) throws -> StoredWebMediaMetadata {
        let metadataURL = directory.appendingPathComponent("metadata.json", isDirectory: false)
        let data = try Data(contentsOf: metadataURL)
        var metadata = try JSONDecoder().decode(StoredWebMediaMetadata.self, from: data)
        if metadata.pendingStorageTransition != nil {
            return try completeStorageTransition(metadata, foundIn: directory)
        }
        // Legacy moves did not persist intent. Preserve their physical-root
        // normalization, but never invent a lost retention request.
        metadata.storageScope = storageScope
        return metadata
    }

    private func writeMetadata(_ metadata: StoredWebMediaMetadata, in directory: URL) throws {
        let metadataURL = directory.appendingPathComponent("metadata.json", isDirectory: false)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func deletePayloadFiles(in directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents where url.lastPathComponent != "metadata.json" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func deleteCompletedArtifacts(in directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents where url.lastPathComponent != "metadata.json"
            && url.lastPathComponent != WebMediaAssetDownloader.partialMediaFilename
            && url.lastPathComponent != WebMediaAssetDownloader.partialIdentityFilename {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func deleteDirectoryIfPresent(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func storedMediaIdentifier(for item: WebMediaInfo) -> String {
        let digest = SHA256.hash(data: Data(item.resourceLookupKey.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func preferredStoredOrdering(_ lhs: StoredWebMedia, _ rhs: StoredWebMedia) -> Bool {
        if lhs.storageScope != rhs.storageScope {
            return lhs.storageScope == .persistent
        }
        return lhs.lastAccessedAt > rhs.lastAccessedAt
    }

    private static func preferredStoredMetadataOrdering(
        _ lhs: StoredWebMediaMetadata,
        _ rhs: StoredWebMediaMetadata
    ) -> Bool {
        if lhs.storageScope != rhs.storageScope {
            return lhs.storageScope == .persistent
        }
        return (lhs.lastAccessedAt ?? lhs.downloadedAt ?? .distantPast)
            > (rhs.lastAccessedAt ?? rhs.downloadedAt ?? .distantPast)
    }

    private func touchAndMakeStoredMedia(_ metadata: StoredWebMediaMetadata) throws -> StoredWebMedia? {
        var touchedMetadata = metadata
        let rootDirectory = directoryURL(for: metadata.id, scope: metadata.storageScope)
        let now = Date()
        touchedMetadata.lastAccessedAt = now
        touchedMetadata.updatedAt = now
        try writeMetadata(touchedMetadata, in: rootDirectory)
        return touchedMetadata.makeStoredMedia(rootDirectory: rootDirectory)
    }

    private static func preferredDownloadOrdering(_ lhs: WebMediaDownloadRecord, _ rhs: WebMediaDownloadRecord) -> Bool {
        if lhs.storageScope != rhs.storageScope {
            return lhs.storageScope == .persistent
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func makeDownloadRecord(from stored: StoredWebMedia) -> WebMediaDownloadRecord {
        WebMediaDownloadRecord(
            id: stored.id,
            mediaInfo: stored.mediaInfo,
            storedMediaState: stored.storedMediaState,
            storageScope: stored.storageScope,
            retentionPolicy: stored.retentionPolicy,
            state: .downloaded,
            resolvedMediaURL: stored.resolvedMediaURL,
            localMediaURL: stored.localMediaURL,
            localThumbnailURL: stored.localThumbnailURL,
            mimeType: stored.mimeType,
            byteCount: stored.byteCount,
            resolutionMethod: stored.resolutionMethod,
            progress: WebMediaDownloadProgress(
                id: stored.id,
                fractionCompleted: 1,
                bytesDownloaded: stored.byteCount ?? 0,
                totalBytesExpected: stored.byteCount
            ),
            failureDescription: nil,
            createdAt: stored.downloadedAt,
            updatedAt: stored.downloadedAt,
            downloadedAt: stored.downloadedAt
        )
    }
}

private struct WebMediaStorageTransition: Codable, Hashable, Sendable {
    let scope: WebMediaOfflineStorageScope
    let retentionPolicy: WebMediaRetentionPolicy
}

private struct StoredWebMediaMetadata: Codable, Hashable, Sendable {
    var id: String
    var mediaInfo: WebMediaInfo
    var storageScope: WebMediaOfflineStorageScope
    var retentionPolicy: WebMediaRetentionPolicy
    var resolvedMedia: ResolvedWebMediaSnapshot
    var state: WebMediaDownloadState
    var createdAt: Date
    var updatedAt: Date
    var downloadedAt: Date?
    var lastAccessedAt: Date?
    var progress: WebMediaDownloadProgress?
    var failureDescription: String?
    var mediaRelativePath: String?
    var thumbnailRelativePath: String?
    var byteCount: Int64?
    var thumbnailRequest: WebMediaThumbnailRequest
    var downloadAttemptIdentifier: UUID? = nil
    var pendingStorageTransition: WebMediaStorageTransition? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case mediaInfo
        case legacyPlaylistInfo = "playlistInfo"
        case storageScope
        case retentionPolicy
        case resolvedMedia
        case state
        case createdAt
        case updatedAt
        case downloadedAt
        case lastAccessedAt
        case progress
        case failureDescription
        case mediaRelativePath
        case thumbnailRelativePath
        case byteCount
        case thumbnailRequest
        case downloadAttemptIdentifier
        case pendingStorageTransition
    }

    init(
        id: String,
        mediaInfo: WebMediaInfo,
        storageScope: WebMediaOfflineStorageScope,
        retentionPolicy: WebMediaRetentionPolicy,
        resolvedMedia: ResolvedWebMediaSnapshot,
        state: WebMediaDownloadState,
        createdAt: Date,
        updatedAt: Date,
        downloadedAt: Date?,
        lastAccessedAt: Date?,
        progress: WebMediaDownloadProgress?,
        failureDescription: String?,
        mediaRelativePath: String?,
        thumbnailRelativePath: String?,
        byteCount: Int64?,
        thumbnailRequest: WebMediaThumbnailRequest
    ) {
        self.id = id
        self.mediaInfo = mediaInfo
        self.storageScope = storageScope
        self.retentionPolicy = retentionPolicy
        self.resolvedMedia = resolvedMedia
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.downloadedAt = downloadedAt
        self.lastAccessedAt = lastAccessedAt
        self.progress = progress
        self.failureDescription = failureDescription
        self.mediaRelativePath = mediaRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.byteCount = byteCount
        self.thumbnailRequest = thumbnailRequest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pendingStorageTransition = try container.decodeIfPresent(
            WebMediaStorageTransition.self, forKey: .pendingStorageTransition
        )
        self.id = try container.decode(String.self, forKey: .id)
        self.mediaInfo = try container.decodeIfPresent(WebMediaInfo.self, forKey: .mediaInfo)
            ?? container.decode(WebMediaInfo.self, forKey: .legacyPlaylistInfo)
        self.storageScope = try container.decode(WebMediaOfflineStorageScope.self, forKey: .storageScope)
        self.retentionPolicy =
            try container.decodeIfPresent(WebMediaRetentionPolicy.self, forKey: .retentionPolicy)
            ?? .default(for: storageScope)
        self.resolvedMedia = try container.decode(ResolvedWebMediaSnapshot.self, forKey: .resolvedMedia)
        self.state = try container.decode(WebMediaDownloadState.self, forKey: .state)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.downloadedAt = try container.decodeIfPresent(Date.self, forKey: .downloadedAt)
        self.lastAccessedAt =
            try container.decodeIfPresent(Date.self, forKey: .lastAccessedAt)
            ?? self.downloadedAt
        self.progress = try container.decodeIfPresent(WebMediaDownloadProgress.self, forKey: .progress)
        self.failureDescription = try container.decodeIfPresent(String.self, forKey: .failureDescription)
        self.mediaRelativePath = try container.decodeIfPresent(String.self, forKey: .mediaRelativePath)
        self.thumbnailRelativePath = try container.decodeIfPresent(String.self, forKey: .thumbnailRelativePath)
        self.byteCount = try container.decodeIfPresent(Int64.self, forKey: .byteCount)
        self.thumbnailRequest =
            try container.decodeIfPresent(WebMediaThumbnailRequest.self, forKey: .thumbnailRequest)
            ?? .automatic()
        self.downloadAttemptIdentifier = try container.decodeIfPresent(UUID.self, forKey: .downloadAttemptIdentifier)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mediaInfo, forKey: .mediaInfo)
        try container.encode(storageScope, forKey: .storageScope)
        try container.encode(retentionPolicy, forKey: .retentionPolicy)
        try container.encode(resolvedMedia, forKey: .resolvedMedia)
        try container.encode(state, forKey: .state)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(downloadedAt, forKey: .downloadedAt)
        try container.encodeIfPresent(lastAccessedAt, forKey: .lastAccessedAt)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(failureDescription, forKey: .failureDescription)
        try container.encodeIfPresent(mediaRelativePath, forKey: .mediaRelativePath)
        try container.encodeIfPresent(thumbnailRelativePath, forKey: .thumbnailRelativePath)
        try container.encodeIfPresent(byteCount, forKey: .byteCount)
        try container.encode(thumbnailRequest, forKey: .thumbnailRequest)
        try container.encodeIfPresent(downloadAttemptIdentifier, forKey: .downloadAttemptIdentifier)
        try container.encodeIfPresent(pendingStorageTransition, forKey: .pendingStorageTransition)
    }

    func makeStoredMedia(rootDirectory: URL) -> StoredWebMedia? {
        guard state == .downloaded,
              let mediaRelativePath,
              let downloadedAt
        else {
            return nil
        }

        return StoredWebMedia(
            id: id,
            mediaInfo: mediaInfo,
            storedMediaState: .make(downloadState: state, storageScope: storageScope),
            storageScope: storageScope,
            retentionPolicy: retentionPolicy,
            resolvedMediaURL: resolvedMedia.resolvedMediaURL,
            localMediaURL: rootDirectory.appendingPathComponent(mediaRelativePath, isDirectory: false),
            localThumbnailURL: thumbnailRelativePath.map {
                rootDirectory.appendingPathComponent($0, isDirectory: false)
            },
            mimeType: resolvedMedia.mimeType,
            byteCount: byteCount,
            resolutionMethod: resolvedMedia.resolutionMethod,
            downloadedAt: downloadedAt,
            lastAccessedAt: lastAccessedAt ?? downloadedAt
        )
    }

    func makeDownloadRecord(rootDirectory: URL) -> WebMediaDownloadRecord {
        WebMediaDownloadRecord(
            id: id,
            mediaInfo: mediaInfo,
            storedMediaState: .make(downloadState: state, storageScope: storageScope),
            storageScope: storageScope,
            retentionPolicy: retentionPolicy,
            state: state,
            resolvedMediaURL: resolvedMedia.resolvedMediaURL,
            localMediaURL: mediaRelativePath.map { rootDirectory.appendingPathComponent($0, isDirectory: false) },
            localThumbnailURL: thumbnailRelativePath.map { rootDirectory.appendingPathComponent($0, isDirectory: false) },
            mimeType: resolvedMedia.mimeType,
            byteCount: byteCount,
            resolutionMethod: resolvedMedia.resolutionMethod,
            progress: progress,
            failureDescription: failureDescription,
            createdAt: createdAt,
            updatedAt: updatedAt,
            downloadedAt: downloadedAt
        )
    }
}

private enum StoredWebMediaThumbnailStore {
    static func generateMediaThumbnail(
        from mediaURL: URL,
        preferredFrameTime: TimeInterval,
        directory: URL
    ) throws -> String? {
        let asset = AVURLAsset(url: mediaURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: preferredFrameTime, preferredTimescale: 600)
        guard let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }

        let relativePath = "thumbnail.jpg"
        let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
        try writeJPEG(cgImage, to: destinationURL)
        return relativePath
    }

    static func storeRemoteThumbnail(
        from url: URL,
        headers: [String: String],
        directory: URL,
        using session: URLSession
    ) async throws -> String? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WebMediaOfflineStoreError.invalidResponse
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw WebMediaOfflineStoreError.invalidHTTPStatus(response.statusCode)
        }

        let fileExtension = WebMediaMimeTypeDetector.preferredFileExtension(
            url: url,
            mimeType: response.value(forHTTPHeaderField: "Content-Type"),
            leadingData: Data(data.prefix(4096)),
            fallback: "jpg"
        )
        let relativePath = "thumbnail.\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
        try data.write(to: destinationURL, options: .atomic)
        return relativePath
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw WebMediaOfflineStoreError.thumbnailGenerationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WebMediaOfflineStoreError.thumbnailGenerationFailed
        }
    }
}

private enum StoredWebMediaFileSystem {
    static func directorySize(at url: URL) throws -> Int64 {
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }

        if total == 0,
           let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
           values.isRegularFile == true {
            total = Int64(values.fileSize ?? 0)
        }

        return total
    }
}
