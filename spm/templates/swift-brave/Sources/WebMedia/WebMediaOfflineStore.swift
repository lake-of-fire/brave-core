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

    public var resourceLookupKey: String { mediaInfo.resourceLookupKey }

    /// `id` names this local artifact; the original page resource remains the
    /// playback owner even though AVFoundation reads a file URL.
    public func makeResolvedMedia(for owner: WebMediaInfo? = nil) -> ResolvedWebMedia {
        ResolvedWebMedia(mediaInfo: owner ?? mediaInfo, url: localMediaURL, mimeType: mimeType,
                         requestHeaders: [:], resolutionMethod: resolutionMethod)
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

public struct WebMediaOfflineRecoveryIssue: Hashable, Sendable {
    public let directoryURL: URL
    public let description: String
}

public protocol WebMediaArtifactDownloading: AnyObject, Sendable {
    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact
}

public struct DownloadedWebMediaArtifact: Codable, Hashable, Sendable {
    public let relativeMediaPath: String
    public let mimeType: String?
    public let byteCount: Int64?

    public init(relativeMediaPath: String, mimeType: String?, byteCount: Int64?) {
        self.relativeMediaPath = relativeMediaPath
        self.mimeType = mimeType
        self.byteCount = byteCount
    }
}

struct WebMediaDownloadedArtifactReceipt: Codable {
    let artifact: DownloadedWebMediaArtifact
    let requestKey: String

    static func requestKey(for media: ResolvedWebMedia) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let value = media.mediaInfo.resourceLookupKey + "\u{1F}" + media.url.absoluteString
            + "\u{1F}" + String(decoding: try encoder.encode(media.requestHeaders), as: UTF8.self)
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
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
        try Task.checkCancellation()
        if media.url.isFileURL {
            let access = media.url.startAccessingSecurityScopedResource()
            defer { if access { media.url.stopAccessingSecurityScopedResource() } }
            let values = try media.url.resourceValues(forKeys: [.isRegularFileKey])
            // Native HLS packages keep AVFoundation's original location. They
            // are reused through the offline store's owned reference, never
            // imported by a generic file copier.
            guard values.isRegularFile == true, media.url.pathExtension.lowercased() != "hlsref" else {
                throw WebMediaOfflineStoreError.invalidResponse
            }
            let fileExtension = WebMediaMimeTypeDetector.preferredFileExtension(
                url: media.url, mimeType: media.mimeType, fallback: "media"
            )
            let relativePath = "media-\(UUID().uuidString).\(fileExtension)"
            let target = directory.appendingPathComponent(relativePath)
            do {
                try FileManager.default.copyItem(at: media.url, to: target)
                try Task.checkCancellation()
                let byteCount = try StoredWebMediaFileSystem.directorySize(at: target)
                guard byteCount > 0 else { throw WebMediaOfflineStoreError.invalidResponse }
                onProgress(.init(id: identifier, fractionCompleted: 1, bytesDownloaded: byteCount, totalBytesExpected: byteCount))
                return .init(relativeMediaPath: relativePath, mimeType: media.mimeType, byteCount: byteCount)
            } catch {
                try? FileManager.default.removeItem(at: target)
                throw error
            }
        }
        if media.containerKind == .hls {
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
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void,
        permitsFreshRestart: Bool = true
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

        let (bytes, response) = try await urlSession.bytes(for: request, delegate: WebMediaRequestRedirectPolicy(url: media.url))
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            throw WebMediaOfflineStoreError.invalidResponse
        }
        guard response.statusCode == 200 || response.statusCode == 206 else {
            if response.statusCode == 416 {
                // 416 is not proof that our prefix is complete. Invalidate the
                // resume identity and perform one bounded, unconditional GET.
                try? FileManager.default.removeItem(at: identityURL)
                if canResume && permitsFreshRestart {
                    bytes.task.cancel()
                    try Task.checkCancellation()
                    return try await downloadFile(media: media, into: directory, identifier: identifier,
                                                  onProgress: onProgress, permitsFreshRestart: false)
                }
            }
            throw WebMediaOfflineStoreError.invalidHTTPStatus(response.statusCode)
        }
        let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard encoding == nil || encoding == "identity" else {
            throw WebMediaOfflineStoreError.invalidResponse
        }
        let responseMimeType = response.value(forHTTPHeaderField: "Content-Type")
        let responseMedia = ResolvedWebMedia(mediaInfo: media.mediaInfo, url: media.url,
                                            mimeType: responseMimeType ?? media.mimeType,
                                            requestHeaders: media.requestHeaders,
                                            resolutionMethod: media.resolutionMethod)
        if responseMedia.containerKind == .hls {
            bytes.task.cancel()
            return try await hlsDownloaderFactory().download(
                media: responseMedia, into: directory, identifier: identifier, onProgress: onProgress
            )
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
                if permitsFreshRestart {
                    bytes.task.cancel()
                    try Task.checkCancellation()
                    return try await downloadFile(media: media, into: directory, identifier: identifier,
                                                  onProgress: onProgress, permitsFreshRestart: false)
                }
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

            if !shouldAppend, sniffData.count == 512,
               WebMediaMimeTypeDetector(data: sniffData).mimeType == "application/vnd.apple.mpegurl" {
                bytes.task.cancel()
                try fileHandle.close()
                try? FileManager.default.removeItem(at: identityURL)
                try? FileManager.default.removeItem(at: temporaryURL)
                let hlsMedia = ResolvedWebMedia(mediaInfo: media.mediaInfo, url: media.url,
                                               mimeType: "application/vnd.apple.mpegurl",
                                               requestHeaders: media.requestHeaders,
                                               resolutionMethod: media.resolutionMethod)
                return try await hlsDownloaderFactory().download(
                    media: hlsMedia, into: directory, identifier: identifier, onProgress: onProgress
                )
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

        guard totalBytesWritten > 0 else { throw WebMediaOfflineStoreError.invalidResponse }
        if WebMediaMimeTypeDetector(data: sniffData).mimeType == "application/vnd.apple.mpegurl" {
            try? FileManager.default.removeItem(at: identityURL)
            try? FileManager.default.removeItem(at: temporaryURL)
            let hlsMedia = ResolvedWebMedia(mediaInfo: media.mediaInfo, url: media.url,
                                           mimeType: "application/vnd.apple.mpegurl",
                                           requestHeaders: media.requestHeaders,
                                           resolutionMethod: media.resolutionMethod)
            return try await hlsDownloaderFactory().download(
                media: hlsMedia, into: directory, identifier: identifier, onProgress: onProgress
            )
        }

        let fileExtension = WebMediaMimeTypeDetector.preferredFileExtension(
            url: media.url,
            mimeType: responseMimeType ?? media.mimeType,
            leadingData: sniffData,
            fallback: "mp4"
        )

        let finalRelativePath = "media-\(UUID().uuidString).\(fileExtension)"
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
        public var legacyPersistentRootURLs: [URL]
        public var legacyTransientRootURLs: [URL]

        public init(
            persistentRootURL: URL? = nil,
            transientRootURL: URL? = nil,
            excludeFromBackup: Bool = true,
            transientStoragePolicy: TransientStoragePolicy = .init(),
            legacyPersistentRootURLs: [URL]? = nil,
            legacyTransientRootURLs: [URL]? = nil
        ) {
            self.persistentRootURL = persistentRootURL ?? Self.defaultPersistentRootURL()
            self.transientRootURL = transientRootURL ?? Self.defaultTransientRootURL()
            self.legacyPersistentRootURLs = legacyPersistentRootURLs
                ?? (persistentRootURL == nil ? [Self.legacyPersistentRootURL()] : [])
            self.legacyTransientRootURLs = legacyTransientRootURLs
                ?? (transientRootURL == nil ? [Self.legacyTransientRootURL()] : [])
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

    }

    public static let shared = WebMediaOfflineStore()

    private let configuration: Configuration
    private let downloader: any WebMediaArtifactDownloading
    private let urlSession: URLSession
    private var activeDownloads: [String: ActiveDownload] = [:]
    private var thumbnailAttempts: [String: UUID] = [:]
    private var downloadWaiters: [String: [UUID: CheckedContinuation<StoredWebMedia, Error>]] = [:]
    private var eventSubscriptions: [UUID: EventSubscription] = [:]
    private var usageLeases: [String: Set<UUID>] = [:]
    private var pendingAutomaticRemovals: Set<String> = []
    private var metadataRecoveryIssues: [URL: WebMediaOfflineRecoveryIssue] = [:]
    private var hasMigratedLegacyItems = false

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
            || (existingRecord?.state == .downloaded && existingRecord?.localMediaURL == nil)

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
            guard !FileManager.default.fileExists(atPath: itemDirectory.path) else {
                // An unreadable/unclassified directory is not an empty slot.
                throw WebMediaOfflineStoreError.storageTransitionConflict
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
        WebMediaHLSAssetDownloader.reconnectBackgroundDownloads()
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

        if metadata.state == .downloaded,
           metadata.makeStoredMedia(rootDirectory: directoryURL(for: id, scope: metadata.storageScope)) != nil {
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
        try allDownloadRecords().first(where: { $0.mediaInfo.referencesSameResource(as: item) })
    }

    public func currentDownloadRecord(id: String) throws -> WebMediaDownloadRecord? {
        try prepareRootsIfNeeded()
        guard let metadata = try loadMetadata(id: id) else {
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
        let candidates = try loadAllMetadata()
                .filter { $0.state == .downloaded && $0.mediaInfo.referencesSameResource(as: item) }
                .sorted(by: Self.preferredStoredMetadataOrdering)
        for metadata in candidates {
            if let stored = try touchAndMakeStoredMedia(metadata) { return stored }
        }
        return nil
    }

    public func storedMedia(forPageURL pageURL: URL) throws -> [StoredWebMedia] {
        let pageLookupKey = WebMediaInfo.pageLookupKey(for: pageURL.absoluteString)
        return try allStoredMedia()
            .filter { $0.pageLookupKey == pageLookupKey }
            .sorted(by: Self.preferredStoredOrdering)
    }

    public func bestStoredMedia(forPageURL pageURL: URL) throws -> StoredWebMedia? {
        let candidates = try loadAllMetadata()
                .filter {
                    $0.state == .downloaded
                        && $0.mediaInfo.pageLookupKey == WebMediaInfo.pageLookupKey(for: pageURL.absoluteString)
                }
                .sorted(by: Self.preferredStoredMetadataOrdering)
        for metadata in candidates {
            if let stored = try touchAndMakeStoredMedia(metadata) { return stored }
        }
        return nil
    }

    public func storedMedia(id: String) throws -> StoredWebMedia? {
        try prepareRootsIfNeeded()
        guard let metadata = try loadMetadata(id: id), metadata.state == .downloaded else {
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
        guard Self.isSafeIdentifier(id) else { throw WebMediaOfflineStoreError.mediaNotFound }
        // Explicit deletion remains available even when metadata recovery is
        // impossible. Automatic cleanup only supplies classified record IDs.
        let existingRecord = try? currentDownloadRecord(id: id)
        usageLeases.removeValue(forKey: id)
        pendingAutomaticRemovals.remove(id)
        thumbnailAttempts.removeValue(forKey: id)
        activeDownloads.removeValue(forKey: id)?.task.cancel()
        finishWaiters(id: id, result: .failure(WebMediaOfflineStoreError.downloadCancelled))
        WebMediaHLSAssetDownloader.discardArtifacts(identifier: id)
        for scope in WebMediaOfflineStorageScope.allCases {
            try WebMediaNativeHLSAssets.removeCompletedReferences(in: directoryURL(for: id, scope: scope), identifier: id)
            try deleteDirectoryIfPresent(directoryURL(for: id, scope: scope))
            try deleteDirectoryIfPresent(downloadStagingRoot(for: id, scope: scope))
        }
        emit(WebMediaDownloadEvent(id: id, kind: .deleted, record: existingRecord))
    }

    public func deleteAllStoredMedia(scope: WebMediaOfflineStorageScope? = nil) throws {
        let allRecords = try allDownloadRecords()
        for record in allRecords where scope == nil || record.storageScope == scope {
            try deleteStoredMedia(id: record.id)
        }
        if scope == nil {
            thumbnailAttempts.removeAll()
            usageLeases.removeAll()
            pendingAutomaticRemovals.removeAll()
            for id in Array(activeDownloads.keys) {
                activeDownloads.removeValue(forKey: id)?.task.cancel()
                finishWaiters(id: id, result: .failure(WebMediaOfflineStoreError.downloadCancelled))
            }
        }
        let scopes = scope.map { [$0] } ?? WebMediaOfflineStorageScope.allCases
        for targetScope in scopes {
            let root = rootURL(for: targetScope)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let protected = Set(allRecords.filter { $0.storageScope != targetScope }.map(\.id))
                .union(scope == nil ? [] : Array(activeDownloads.keys))
            for entry in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                if entry.lastPathComponent == ".download-attempts" {
                    // A terminal item's retention can change while its native
                    // HLS task remains bound to an older staging scope.
                    for attemptRoot in try FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
                        where !protected.contains(attemptRoot.lastPathComponent) {
                        WebMediaHLSAssetDownloader.discardArtifacts(identifier: attemptRoot.lastPathComponent)
                        try deleteDirectoryIfPresent(attemptRoot)
                    }
                } else if !protected.contains(entry.lastPathComponent) {
                    if Self.isSafeIdentifier(entry.lastPathComponent),
                       (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        WebMediaHLSAssetDownloader.discardArtifacts(identifier: entry.lastPathComponent)
                        try WebMediaNativeHLSAssets.removeCompletedReferences(in: entry, identifier: entry.lastPathComponent)
                    }
                    try deleteDirectoryIfPresent(entry)
                }
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
                try automaticallyRemoveStoredMedia(id: record.id)
            }
        }
    }

    public func handleSessionDidEnd() throws {
        let transientRecords = try allDownloadRecords().filter {
            $0.storageScope == .transient &&
                ($0.retentionPolicy == .untilPageChange || $0.retentionPolicy == .untilSessionEnds)
        }
        for record in transientRecords {
            try automaticallyRemoveStoredMedia(id: record.id)
        }
    }

    /// Holds a validated artifact while a native player or extractor reads it.
    /// Explicit user deletion is still allowed; automatic retention waits.
    public func retainStoredMedia(id: String) throws -> UUID {
        guard try storedMedia(id: id) != nil else { throw WebMediaOfflineStoreError.mediaNotFound }
        let lease = UUID()
        usageLeases[id, default: []].insert(lease)
        return lease
    }

    public func releaseStoredMedia(id: String, leaseID: UUID) {
        guard usageLeases[id]?.remove(leaseID) != nil else { return }
        guard usageLeases[id]?.isEmpty == true else { return }
        usageLeases.removeValue(forKey: id)
        _ = try? loadAllMetadata()
        if pendingAutomaticRemovals.remove(id) != nil,
           let metadata = try? loadMetadata(id: id), metadata.storageScope == .transient {
            try? deleteStoredMedia(id: id)
        }
        try? enforceTransientStoragePolicy(excluding: [], exceptPageLookupKeys: [])
    }

    private func automaticallyRemoveStoredMedia(id: String) throws {
        if usageLeases[id]?.isEmpty == false {
            pendingAutomaticRemovals.insert(id)
            return
        }
        try deleteStoredMedia(id: id)
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
              let mediaRelativePath = metadata.mediaRelativePath,
              let mediaURL = StoredWebMediaFileSystem.validatedPayloadURL(
                relativePath: mediaRelativePath, rootDirectory: itemDirectory,
                expectedByteCount: metadata.byteCount, expectedOwnerIdentifier: id
              )
        else {
            return metadata.makeStoredMedia(rootDirectory: itemDirectory)
        }

        let usageLease = try retainStoredMedia(id: id)
        defer { releaseStoredMedia(id: id, leaseID: usageLease) }

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
            // Restored background tasks own this exact working directory. A
            // new in-memory attempt fence must not relocate or delete it.
            let storageAttemptID = metadata.downloadAttemptIdentifier ?? attemptID
            let stagingScope = metadata.downloadAttemptStorageScope ?? metadata.storageScope
            let stagingDirectory = downloadStagingDirectory(
                for: identifier,
                scope: stagingScope,
                attemptID: storageAttemptID
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
                // A completed transport or HLS journal survives a failed
                // presentation/metadata step and is reused by the next attempt.
                if shouldDeleteStagingDirectory,
                   !FileManager.default.fileExists(atPath: stagingDirectory.appendingPathComponent(".downloaded-artifact.json").path),
                   !FileManager.default.fileExists(atPath: stagingDirectory.appendingPathComponent(".hls-transfer.json").path) {
                    try? deleteDirectoryIfPresent(stagingDirectory)
                }
            }
            if !FileManager.default.fileExists(atPath: stagedPartialURL.path),
               FileManager.default.fileExists(atPath: existingPartialURL.path) {
                try FileManager.default.copyItem(at: existingPartialURL, to: stagedPartialURL)
                let resumeIdentityURL = existingPartialURL.deletingLastPathComponent()
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
            metadata.downloadAttemptIdentifier = storageAttemptID
            metadata.downloadAttemptStorageScope = stagingScope
            metadata.updatedAt = Date()
            metadata.failureDescription = nil
            try writeMetadata(metadata, in: itemDirectory)
            emit(
                WebMediaDownloadEvent(
                    id: identifier,
                    kind: .downloading,
                    record: metadata.makeDownloadRecord(rootDirectory: itemDirectory)
                )
            )

            let artifact: DownloadedWebMediaArtifact
            let artifactReceipt = stagingDirectory.appendingPathComponent(".downloaded-artifact.json")
            let resolvedMedia = metadata.resolvedMedia.makeResolvedMedia()
            let artifactRequestKey = try WebMediaDownloadedArtifactReceipt.requestKey(for: resolvedMedia)
            if let data = try? Data(contentsOf: artifactReceipt),
               let saved = try? JSONDecoder().decode(WebMediaDownloadedArtifactReceipt.self, from: data),
               saved.requestKey == artifactRequestKey,
               StoredWebMediaFileSystem.validatedPayloadURL(relativePath: saved.artifact.relativeMediaPath,
                                                            rootDirectory: stagingDirectory,
                                                            expectedByteCount: saved.artifact.byteCount, expectedOwnerIdentifier: identifier) != nil {
                artifact = saved.artifact
            } else {
                artifact = try await downloader.download(
                    media: resolvedMedia,
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
                try JSONEncoder().encode(WebMediaDownloadedArtifactReceipt(artifact: artifact, requestKey: artifactRequestKey))
                    .write(to: artifactReceipt, options: .atomic)
            }

            try Task.checkCancellation()

            guard isCurrentDownloadAttempt(identifier: identifier, attemptID: attemptID),
                  let currentMetadata = try loadMetadata(id: identifier),
                  currentMetadata.state == .downloading
            else {
                return
            }

            metadata = currentMetadata
            let currentItemDirectory = directoryURL(for: identifier, scope: metadata.storageScope)

            guard let mediaURL = StoredWebMediaFileSystem.validatedPayloadURL(
                relativePath: artifact.relativeMediaPath, rootDirectory: stagingDirectory,
                expectedByteCount: artifact.byteCount, expectedOwnerIdentifier: identifier
            ) else { throw WebMediaOfflineStoreError.downloadNotFinished }
            // Thumbnails are optional derived data, never the commit authority
            // for a successfully downloaded media payload.
            let thumbnailRelativePath: String?
            do {
                thumbnailRelativePath = try await storeThumbnail(
                    metadata.thumbnailRequest,
                    mediaURL: mediaURL,
                    directory: stagingDirectory,
                    shouldMaterializeImmediately: metadata.thumbnailRequest.loadingPolicy == .eager
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                thumbnailRelativePath = nil
            }

            try Task.checkCancellation()

            metadata.state = .downloaded
            metadata.downloadAttemptIdentifier = nil
            metadata.downloadAttemptStorageScope = nil
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
            let commit = WebMediaArtifactCommit(metadata: metadata, attemptID: storageAttemptID, stagingScope: stagingScope)
            try JSONEncoder().encode(commit).write(
                to: currentItemDirectory.appendingPathComponent(".download-commit.json"), options: .atomic
            )
            let committed = try completeDownloadCommit(commit, in: currentItemDirectory)
            guard let stored = committed.makeStoredMedia(rootDirectory: currentItemDirectory) else {
                throw WebMediaOfflineStoreError.downloadNotFinished
            }
            WebMediaHLSAssetDownloader.acknowledgeArtifact(in: stagingDirectory)
            try? deleteDirectoryIfPresent(stagingDirectory)

            if metadata.storageScope == .transient {
                try? enforceTransientStoragePolicy(excluding: [identifier], exceptPageLookupKeys: [])
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
        guard var metadata = try? loadMetadata(id: identifier), metadata.state == .downloading else {
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

        if metadata.state == .downloaded,
           let stored = metadata.makeStoredMedia(rootDirectory: directoryURL(for: identifier, scope: metadata.storageScope)) {
            finishWaiters(id: identifier, result: .success(stored))
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

        if metadata.state == .downloaded,
           let stored = metadata.makeStoredMedia(rootDirectory: directoryURL(for: identifier, scope: metadata.storageScope)) {
            finishWaiters(id: identifier, result: .success(stored))
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
            guard imageData.count <= 10 * 1024 * 1024,
                  !fileExtension.isEmpty, fileExtension.count <= 12,
                  fileExtension.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
                throw WebMediaOfflineStoreError.thumbnailGenerationFailed
            }
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
        let excludedIDs = excludedIDs.union(usageLeases.keys).union(activeDownloads.keys)
        let policy = configuration.transientStoragePolicy
        guard policy.maxItemCount != nil || policy.maxTotalByteCount != nil || policy.maxAge != nil else { return }

        // Completed artifacts and retained failed/cancelled attempts share one
        // budget. Native package bytes live outside the small reference files.
        var records = try allDownloadRecords(states: [.downloaded, .failed, .cancelled])
            .filter { $0.storageScope == .transient }
        let stored = try allStoredMedia(scope: .transient)
        let lastAccess = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.lastAccessedAt) })
        records.sort { (lastAccess[$0.id] ?? $0.updatedAt) < (lastAccess[$1.id] ?? $1.updatedAt) }
        let mayRemove: (WebMediaDownloadRecord) -> Bool = {
            !excludedIDs.contains($0.id) && !exceptPageLookupKeys.contains($0.pageLookupKey)
        }
        if let maxAge = policy.maxAge {
            let now = Date()
            for record in records where mayRemove(record)
                && now.timeIntervalSince(lastAccess[record.id] ?? record.updatedAt) > max(0, maxAge) {
                try automaticallyRemoveStoredMedia(id: record.id)
                records.removeAll { $0.id == record.id }
            }
        }
        if let maxItemCount = policy.maxItemCount {
            while records.count > max(0, maxItemCount), let record = records.first(where: mayRemove) {
                try automaticallyRemoveStoredMedia(id: record.id)
                records.removeAll { $0.id == record.id }
            }
        }
        if let maxTotalByteCount = policy.maxTotalByteCount {
            var sizes = [String: Int64]()
            for record in records { sizes[record.id] = try retainedByteCount(id: record.id) }
            let totalSize: () -> Int64 = {
                sizes.values.reduce(Int64(0)) { total, size in
                    let (sum, overflow) = total.addingReportingOverflow(max(0, size))
                    return overflow ? Int64.max : sum
                }
            }
            while totalSize() > max(0, maxTotalByteCount), let record = records.first(where: mayRemove) {
                try automaticallyRemoveStoredMedia(id: record.id)
                records.removeAll { $0.id == record.id }
                sizes.removeValue(forKey: record.id)
            }
        }
    }

    private func retainedByteCount(id: String) throws -> Int64 {
        var total = try WebMediaNativeHLSAssets.byteCount(identifier: id)
        for scope in WebMediaOfflineStorageScope.allCases {
            for directory in [directoryURL(for: id, scope: scope), downloadStagingRoot(for: id, scope: scope)]
                where FileManager.default.fileExists(atPath: directory.path) {
                let (sum, overflow) = total.addingReportingOverflow(try StoredWebMediaFileSystem.directorySize(at: directory))
                total = overflow ? Int64.max : sum
            }
        }
        return total
    }

    private func loadMetadata(id: String) throws -> StoredWebMediaMetadata? {
        guard Self.isSafeIdentifier(id) else { throw WebMediaOfflineStoreError.mediaNotFound }
        var firstError: Error?
        for scope in WebMediaOfflineStorageScope.allCases {
            let directory = directoryURL(for: id, scope: scope)
            if FileManager.default.fileExists(atPath: directory.path) {
                do { return try readMetadata(from: directory, storageScope: scope) }
                catch {
                    if firstError == nil { firstError = error }
                    metadataRecoveryIssues[directory] = .init(directoryURL: directory, description: error.localizedDescription)
                }
            }
        }
        if let firstError { throw firstError }
        return nil
    }

    /// Read failures are visible without making one damaged item hide every
    /// healthy download. Originals are retained for recovery or explicit removal.
    public func recoveryIssues() -> [WebMediaOfflineRecoveryIssue] {
        metadataRecoveryIssues.values.sorted { $0.directoryURL.path < $1.directoryURL.path }
    }

    private func loadAllMetadata() throws -> [StoredWebMediaMetadata] {
        try prepareRootsIfNeeded()
        var byID: [String: StoredWebMediaMetadata] = [:]
        for scope in WebMediaOfflineStorageScope.allCases {
            for metadata in try loadMetadata(in: rootURL(for: scope), storageScope: scope) {
                if let existing = byID[metadata.id], Self.preferredStoredMetadataOrdering(existing, metadata) {
                    continue
                }
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
            do {
                let resourceValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues.isDirectory == true else { continue }
                let metadata = try readMetadata(from: directoryURL, storageScope: storageScope)
                result.append(metadata)
            } catch {
                // One unreadable item must not hide healthy downloads or cause
                // quota cleanup to delete data it cannot classify.
                metadataRecoveryIssues[directoryURL] = .init(directoryURL: directoryURL, description: error.localizedDescription)
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
        if !hasMigratedLegacyItems {
            // This runs on the store actor, not in Configuration's initializer.
            // A preexisting current root may contain only part of an old copy.
            for scope in WebMediaOfflineStorageScope.allCases {
                let legacyRoots = scope == .persistent
                    ? configuration.legacyPersistentRootURLs : configuration.legacyTransientRootURLs
                for legacyRoot in legacyRoots {
                    try migrateLegacyItems(from: legacyRoot, storageScope: scope)
                }
            }
            hasMigratedLegacyItems = true
        }
    }

    private func migrateLegacyItems(from legacyRoot: URL, storageScope: WebMediaOfflineStorageScope) throws {
        let currentRoot = rootURL(for: storageScope)
        guard legacyRoot.standardizedFileURL != currentRoot.standardizedFileURL,
              FileManager.default.fileExists(atPath: legacyRoot.path) else { return }
        // A completed ledger lives outside the erasable media root. Explicit
        // deletion must not resurrect an original retained by an earlier copy.
        let ledger = currentRoot.deletingLastPathComponent().appendingPathComponent(".legacy-media-migrations", isDirectory: true)
        try FileManager.default.createDirectory(at: ledger, withIntermediateDirectories: true)
        for source in try FileManager.default.contentsOfDirectory(at: legacyRoot,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            guard (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let key = SHA256.hash(data: Data((legacyRoot.standardizedFileURL.path + "\u{1F}"
                + currentRoot.standardizedFileURL.path + "\u{1F}" + source.lastPathComponent).utf8))
                .map { String(format: "%02x", $0) }.joined()
            let marker = ledger.appendingPathComponent(key + ".completed")
            if FileManager.default.fileExists(atPath: marker.path) { continue }
            do {
                let data = try Data(contentsOf: source.appendingPathComponent("metadata.json"))
                var metadata = try JSONDecoder().decode(StoredWebMediaMetadata.self, from: data)
                guard metadata.id == source.lastPathComponent, Self.isSafeIdentifier(metadata.id) else {
                    throw WebMediaOfflineStoreError.storageTransitionConflict
                }
                metadata.storageScope = storageScope
                let destination = directoryURL(for: metadata.id, scope: storageScope)
                if FileManager.default.fileExists(atPath: destination.path),
                   let existingData = try? Data(contentsOf: destination.appendingPathComponent("metadata.json")),
                   let existing = try? JSONDecoder().decode(StoredWebMediaMetadata.self, from: existingData) {
                    guard existing.mediaInfo.resourceLookupKey == metadata.mediaInfo.resourceLookupKey else {
                        throw WebMediaOfflineStoreError.storageTransitionConflict
                    }
                    if existing.state != .downloaded || existing.makeStoredMedia(rootDirectory: destination) != nil {
                        try Data(metadata.id.utf8).write(to: marker, options: .atomic)
                        continue
                    }
                }
                if metadata.state == .downloaded, metadata.makeStoredMedia(rootDirectory: source) == nil {
                    throw WebMediaOfflineStoreError.downloadNotFinished
                }
                let staging = ledger.appendingPathComponent(key + ".payload", isDirectory: true)
                // This staging path is ours; its legacy source is untouched.
                if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
                try FileManager.default.copyItem(at: source, to: staging)
                try writeMetadata(metadata, in: staging)
                if let attempt = metadata.downloadAttemptIdentifier {
                    let previous = legacyRoot.appendingPathComponent(".download-attempts", isDirectory: true)
                        .appendingPathComponent(metadata.id, isDirectory: true).appendingPathComponent(attempt.uuidString)
                    let next = downloadStagingDirectory(for: metadata.id, scope: storageScope, attemptID: attempt)
                    if FileManager.default.fileExists(atPath: previous.path),
                       !FileManager.default.fileExists(atPath: next.path) {
                        try FileManager.default.createDirectory(at: next.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: previous, to: next)
                    }
                }
                if FileManager.default.fileExists(atPath: destination.path) {
                    let preserved = ledger.appendingPathComponent(key + ".previous-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.moveItem(at: destination, to: preserved)
                }
                try FileManager.default.moveItem(at: staging, to: destination)
                if metadata.state == .downloaded,
                   metadata.makeStoredMedia(rootDirectory: destination) == nil {
                    // Legacy native packages may bind playback to their old
                    // path. Keep the legacy original and leave the migration
                    // unfinished if its final destination is not usable.
                    throw WebMediaOfflineStoreError.downloadNotFinished
                }
                try Data(metadata.id.utf8).write(to: marker, options: .atomic)
            } catch {
                // A failed copy cannot publish a partial download or erase the
                // original. Other valid legacy items can still be recovered.
                metadataRecoveryIssues[source] = .init(directoryURL: source, description: error.localizedDescription)
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
            for: metadata.id, scope: metadata.downloadAttemptStorageScope ?? metadata.storageScope, attemptID: attemptID
        )
        if FileManager.default.fileExists(atPath: stagingDirectory.appendingPathComponent(".downloaded-artifact.json").path)
            || FileManager.default.fileExists(atPath: stagingDirectory.appendingPathComponent(".hls-transfer.json").path) {
            return
        }
        let partialURL = stagingDirectory.appendingPathComponent(WebMediaAssetDownloader.partialMediaFilename)
        if FileManager.default.fileExists(atPath: partialURL.path) {
            try publishPartial(from: stagingDirectory, to: itemDirectory)
        }
        // Clear the pointer only after its resumable bytes have a durable home.
        // On failure the terminal record retains it for a later retry.
        metadata.downloadAttemptIdentifier = nil
        metadata.downloadAttemptStorageScope = nil
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
        if pending.downloadAttemptIdentifier != nil && pending.downloadAttemptStorageScope == nil {
            pending.downloadAttemptStorageScope = metadata.storageScope
        }
        let source = directoryURL(for: metadata.id, scope: metadata.storageScope)
        pending.pendingStorageTransition = .init(scope: scope, retentionPolicy: retentionPolicy,
                                                  identifier: UUID(), sourceScope: metadata.storageScope)
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
        let isAtDestination = directory.standardizedFileURL == destination.standardizedFileURL
        var existingCommit: StoredWebMediaMetadata?
        if !isAtDestination {
            if FileManager.default.fileExists(atPath: destination.path) {
                let existing = try JSONDecoder().decode(StoredWebMediaMetadata.self,
                    from: Data(contentsOf: destination.appendingPathComponent("metadata.json")))
                guard let transactionID = intent.identifier,
                      existing.id == metadata.id,
                      existing.mediaInfo.resourceLookupKey == metadata.mediaInfo.resourceLookupKey,
                      existing.pendingStorageTransition?.identifier == transactionID
                        || existing.lastStorageTransitionIdentifier == transactionID else {
                    throw WebMediaOfflineStoreError.storageTransitionConflict
                }
                if existing.lastStorageTransitionIdentifier == transactionID,
                   existing.pendingStorageTransition == nil {
                    existingCommit = existing
                }
                if metadata.state == .downloaded {
                    guard let relativePath = metadata.mediaRelativePath,
                          StoredWebMediaFileSystem.validatedPayloadURL(relativePath: relativePath,
                            rootDirectory: destination, expectedByteCount: metadata.byteCount, expectedOwnerIdentifier: metadata.id) != nil else {
                        throw WebMediaOfflineStoreError.downloadNotFinished
                    }
                }
            } else {
                // A complete copy is renamed within the destination root. This
                // also keeps active readers' original file URLs usable until
                // their leases end; cross-volume moves never expose a partial.
                let token = intent.identifier?.uuidString ?? UUID().uuidString
                let staging = rootURL(for: intent.scope).appendingPathComponent(".relocations", isDirectory: true)
                    .appendingPathComponent(metadata.id + "-" + token, isDirectory: true)
                try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
                try FileManager.default.copyItem(at: directory, to: staging)
                if metadata.state == .downloaded {
                    guard let relativePath = metadata.mediaRelativePath,
                          StoredWebMediaFileSystem.validatedPayloadURL(relativePath: relativePath,
                            rootDirectory: staging, expectedByteCount: metadata.byteCount, expectedOwnerIdentifier: metadata.id) != nil else {
                        throw WebMediaOfflineStoreError.downloadNotFinished
                    }
                }
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        }
        if metadata.state == .downloaded {
            guard let relativePath = metadata.mediaRelativePath,
                  StoredWebMediaFileSystem.validatedPayloadURL(relativePath: relativePath,
                    rootDirectory: destination, expectedByteCount: metadata.byteCount,
                    expectedOwnerIdentifier: metadata.id) != nil else {
                // Admission at staging cannot prove that a legacy native
                // package remains playable after the final rename. Its source
                // and transition intent stay intact until this path is usable.
                throw WebMediaOfflineStoreError.downloadNotFinished
            }
        }
        var committed = existingCommit ?? metadata
        if existingCommit == nil {
            committed.storageScope = intent.scope
            committed.retentionPolicy = intent.retentionPolicy
            committed.pendingStorageTransition = nil
            committed.lastStorageTransitionIdentifier = intent.identifier
            try writeMetadata(committed, in: destination)
        }
        // A copied source is removed only after the destination metadata has
        // committed this same transaction. Interrupted cleanup is idempotent.
        if let sourceScope = intent.sourceScope, sourceScope != intent.scope,
           let transactionID = intent.identifier, usageLeases[metadata.id]?.isEmpty != false {
            let source = directoryURL(for: metadata.id, scope: sourceScope)
            if let data = try? Data(contentsOf: source.appendingPathComponent("metadata.json")),
               let old = try? JSONDecoder().decode(StoredWebMediaMetadata.self, from: data),
               old.pendingStorageTransition?.identifier == transactionID {
                try? deleteDirectoryIfPresent(source)
            }
        }
        return committed
    }

    private func readMetadata(
        from directory: URL,
        storageScope: WebMediaOfflineStorageScope
    ) throws -> StoredWebMediaMetadata {
        var primaryError: Error?
        let commitURL = directory.appendingPathComponent(".download-commit.json")
        if FileManager.default.fileExists(atPath: commitURL.path) {
            do {
                let commit = try JSONDecoder().decode(WebMediaArtifactCommit.self, from: Data(contentsOf: commitURL))
                guard commit.metadata.id == directory.lastPathComponent else {
                    throw WebMediaOfflineStoreError.storageTransitionConflict
                }
                return try completeDownloadCommit(commit, in: directory)
            } catch {
                // Preserve the intent and its staged/published payload. A bad
                // recovery record must not hide an older readable commitment.
                primaryError = error
            }
        }
        var metadata: StoredWebMediaMetadata?
        for name in ["metadata.json", ".committed-media.json", ".metadata.previous.json"] {
            do {
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                let candidate = try JSONDecoder().decode(StoredWebMediaMetadata.self, from: data)
                guard Self.isSafeIdentifier(candidate.id), candidate.id == directory.lastPathComponent else {
                    throw WebMediaOfflineStoreError.storageTransitionConflict
                }
                if name != "metadata.json", candidate.state == .downloaded,
                   candidate.makeStoredMedia(rootDirectory: directory) == nil { continue }
                metadata = candidate
                break
            } catch {
                if primaryError == nil { primaryError = error }
            }
        }
        guard var metadata else { throw primaryError ?? WebMediaOfflineStoreError.mediaNotFound }
        if let primaryError {
            metadataRecoveryIssues[directory] = .init(directoryURL: directory, description: primaryError.localizedDescription)
        } else {
            metadataRecoveryIssues.removeValue(forKey: directory)
        }
        if metadata.pendingStorageTransition != nil {
            do { return try completeStorageTransition(metadata, foundIn: directory) }
            catch {
                metadataRecoveryIssues[directory] = .init(directoryURL: directory, description: error.localizedDescription)
                // An unfinished move is still allowed to serve the unchanged
                // source. Keep its intent so the next access retries recovery.
                guard metadata.state == .downloaded,
                      metadata.makeStoredMedia(rootDirectory: directory) != nil else { throw error }
            }
        }
        // Legacy moves did not persist intent. Preserve their physical-root
        // normalization, but never invent a lost retention request.
        metadata.storageScope = storageScope
        return metadata
    }

    private func writeMetadata(_ metadata: StoredWebMediaMetadata, in directory: URL) throws {
        let metadataURL = directory.appendingPathComponent("metadata.json", isDirectory: false)
        if let previous = try? Data(contentsOf: metadataURL) {
            if let decoded = try? JSONDecoder().decode(StoredWebMediaMetadata.self, from: previous),
               decoded.id == metadata.id {
                try previous.write(to: directory.appendingPathComponent(".metadata.previous.json"), options: .atomic)
            } else {
                // Preserve the unreadable original before a later successful
                // operation replaces it with recovered metadata.
                let preserved = directory.appendingPathComponent(".metadata.unreadable.json")
                if !FileManager.default.fileExists(atPath: preserved.path) {
                    try previous.write(to: preserved, options: .atomic)
                }
            }
        }
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
        if metadata.state == .downloaded {
            // The primary atomic write above is the commit point. An optional
            // recovery snapshot failure cannot turn this success into failure.
            try? data.write(to: directory.appendingPathComponent(".committed-media.json"), options: .atomic)
        }
    }

    private func completeDownloadCommit(_ commit: WebMediaArtifactCommit, in directory: URL) throws -> StoredWebMediaMetadata {
        var metadata = commit.metadata
        guard metadata.state == .downloaded, let relativePath = metadata.mediaRelativePath,
              Self.isSafeIdentifier(metadata.id) else { throw WebMediaOfflineStoreError.invalidResponse }
        let staging = downloadStagingDirectory(for: metadata.id, scope: commit.stagingScope ?? metadata.storageScope,
                                              attemptID: commit.attemptID)
        if StoredWebMediaFileSystem.validatedPayloadURL(relativePath: relativePath, rootDirectory: directory,
                                                        expectedByteCount: metadata.byteCount, expectedOwnerIdentifier: metadata.id) == nil {
            guard StoredWebMediaFileSystem.validatedPayloadURL(relativePath: relativePath, rootDirectory: staging,
                                                               expectedByteCount: metadata.byteCount, expectedOwnerIdentifier: metadata.id) != nil else {
                throw WebMediaOfflineStoreError.downloadNotFinished
            }
            try publishArtifact(relativePath: relativePath, from: staging, to: directory)
        }
        if let thumbnail = metadata.thumbnailRelativePath {
            let target = StoredWebMediaFileSystem.validatedPayloadURL(relativePath: thumbnail, rootDirectory: directory)
            if target == nil {
                if StoredWebMediaFileSystem.validatedPayloadURL(relativePath: thumbnail, rootDirectory: staging) != nil {
                    do { try publishArtifact(relativePath: thumbnail, from: staging, to: directory) }
                    catch { metadata.thumbnailRelativePath = nil }
                } else { metadata.thumbnailRelativePath = nil }
            }
        }
        metadata.downloadAttemptIdentifier = nil
        metadata.downloadAttemptStorageScope = nil
        try writeMetadata(metadata, in: directory)
        // Everything after this point is cleanup. None of it may invalidate the
        // published media or send it through destructive failure handling.
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(".download-commit.json"))
        WebMediaHLSAssetDownloader.acknowledgeArtifact(in: staging)
        try? deleteDirectoryIfPresent(staging)
        return metadata
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
        // Publication may already have moved a valid payload before the final
        // metadata write failed. The commit journal owns those recovery bytes.
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent(".download-commit.json").path) else { return }
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

    private static func isSafeIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier != "." && identifier != ".."
            && !identifier.contains("/") && !identifier.contains("\\")
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
        guard let stored = metadata.makeStoredMedia(rootDirectory: rootDirectory) else { return nil }
        let now = Date()
        touchedMetadata.lastAccessedAt = now
        touchedMetadata.updatedAt = now
        // Access bookkeeping is optional; read-only/full storage must not make
        // already committed media disappear from native playback.
        try? writeMetadata(touchedMetadata, in: rootDirectory)
        return touchedMetadata.makeStoredMedia(rootDirectory: rootDirectory) ?? stored
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

private struct WebMediaArtifactCommit: Codable {
    let metadata: StoredWebMediaMetadata
    let attemptID: UUID
    var stagingScope: WebMediaOfflineStorageScope? = nil
}

private struct WebMediaStorageTransition: Codable, Hashable, Sendable {
    let scope: WebMediaOfflineStorageScope
    let retentionPolicy: WebMediaRetentionPolicy
    var identifier: UUID? = nil
    var sourceScope: WebMediaOfflineStorageScope? = nil
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
    var downloadAttemptStorageScope: WebMediaOfflineStorageScope? = nil
    var pendingStorageTransition: WebMediaStorageTransition? = nil
    var lastStorageTransitionIdentifier: UUID? = nil

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
        case downloadAttemptStorageScope
        case pendingStorageTransition
        case lastStorageTransitionIdentifier
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
        self.lastStorageTransitionIdentifier = try container.decodeIfPresent(UUID.self, forKey: .lastStorageTransitionIdentifier)
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
        self.downloadAttemptStorageScope = try container.decodeIfPresent(WebMediaOfflineStorageScope.self, forKey: .downloadAttemptStorageScope)
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
        try container.encodeIfPresent(downloadAttemptStorageScope, forKey: .downloadAttemptStorageScope)
        try container.encodeIfPresent(pendingStorageTransition, forKey: .pendingStorageTransition)
        try container.encodeIfPresent(lastStorageTransitionIdentifier, forKey: .lastStorageTransitionIdentifier)
    }

    func makeStoredMedia(rootDirectory: URL) -> StoredWebMedia? {
        guard state == .downloaded,
              let mediaRelativePath,
              let downloadedAt,
              let localMediaURL = StoredWebMediaFileSystem.validatedPayloadURL(
                relativePath: mediaRelativePath, rootDirectory: rootDirectory, expectedByteCount: byteCount, expectedOwnerIdentifier: id
              )
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
            localMediaURL: localMediaURL,
            localThumbnailURL: thumbnailRelativePath.flatMap {
                StoredWebMediaFileSystem.validatedPayloadURL(relativePath: $0, rootDirectory: rootDirectory)
            },
            mimeType: resolvedMedia.mimeType,
            byteCount: (try? StoredWebMediaFileSystem.directorySize(at: localMediaURL)) ?? byteCount,
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
            localMediaURL: mediaRelativePath.flatMap {
                StoredWebMediaFileSystem.validatedPayloadURL(relativePath: $0, rootDirectory: rootDirectory,
                                                              expectedByteCount: byteCount, expectedOwnerIdentifier: id)
            },
            localThumbnailURL: thumbnailRelativePath.flatMap {
                StoredWebMediaFileSystem.validatedPayloadURL(relativePath: $0, rootDirectory: rootDirectory)
            },
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

        let (bytes, response) = try await session.bytes(for: request, delegate: WebMediaRequestRedirectPolicy(url: url))
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            throw WebMediaOfflineStoreError.invalidResponse
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw WebMediaOfflineStoreError.invalidHTTPStatus(response.statusCode)
        }

        let maximumBytes = 10 * 1024 * 1024
        guard response.expectedContentLength <= maximumBytes else {
            throw WebMediaOfflineStoreError.thumbnailGenerationFailed
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw WebMediaOfflineStoreError.thumbnailGenerationFailed }
            data.append(byte)
        }
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            throw WebMediaOfflineStoreError.thumbnailGenerationFailed
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

enum StoredWebMediaFileSystem {
    static func validatedPayloadURL(
        relativePath: String,
        rootDirectory: URL,
        expectedByteCount: Int64? = nil,
        expectedOwnerIdentifier: String? = nil
    ) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains("..") else { return nil }
        let root = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let url = rootDirectory.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/"),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]) else {
            return nil
        }
        if values.isRegularFile == true {
            if url.pathExtension == "hlsref" {
                guard let size = values.fileSize, size > 0, size <= 16 * 1024,
                      let data = try? Data(contentsOf: url),
                      let reference = try? JSONDecoder().decode(WebMediaNativeHLSReference.self, from: data),
                      expectedOwnerIdentifier.map({ $0 == reference.identifier }) != false,
                      url.lastPathComponent == "media-\(reference.transferIdentifier).hlsref" else { return nil }
                return WebMediaNativeHLSAssets.resolve(reference)
            }
            guard let size = values.fileSize, size > 0,
                  expectedByteCount.map({ $0 == Int64(size) }) != false else { return nil }
            return url
        }
        guard values.isDirectory == true, url.pathExtension.lowercased() == "movpkg",
              let size = try? directorySize(at: url), size > 0,
              AVURLAsset(url: url).assetCache?.isPlayableOffline == true else { return nil }
        return url
    }

    static func directorySize(at url: URL) throws -> Int64 {
        let rootValues = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
        if rootValues.isRegularFile == true { return Int64(max(0, rootValues.fileSize ?? 0)) }
        guard rootValues.isDirectory == true else { throw WebMediaOfflineStoreError.invalidResponse }
        var total: Int64 = 0
        var traversalError: Error?
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        )
        guard let enumerator else { throw WebMediaOfflineStoreError.invalidResponse }

        while let fileURL = enumerator.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                let size = Int64(max(0, values.fileSize ?? 0))
                let (next, overflow) = total.addingReportingOverflow(size)
                guard !overflow else { throw WebMediaOfflineStoreError.invalidResponse }
                total = next
            }
        }

        if let traversalError { throw traversalError }
        return total
    }
}
