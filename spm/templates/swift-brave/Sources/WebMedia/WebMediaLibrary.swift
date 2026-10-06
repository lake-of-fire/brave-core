import Foundation

public actor WebMediaLibrary {
    private let mediaStreamer: WebMediaStreamer
    private let offlineStore: WebMediaOfflineStore

    public init(
        mediaStreamer: WebMediaStreamer = WebMediaStreamer(),
        offlineStore: WebMediaOfflineStore = .shared
    ) {
        self.mediaStreamer = mediaStreamer
        self.offlineStore = offlineStore
    }

    public func resolve(
        _ item: WebMediaInfo,
        requestContext: WebMediaRequestContext = .init()
    ) async throws -> ResolvedWebMedia {
        try await mediaStreamer.resolveMedia(item, requestContext: requestContext)
    }

    public func download(
        _ item: WebMediaInfo,
        requestContext: WebMediaRequestContext = .init(),
        storageScope: WebMediaOfflineStorageScope,
        retentionPolicy: WebMediaRetentionPolicy? = nil,
        thumbnail: WebMediaThumbnailRequest = .automatic(),
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) async throws -> StoredWebMedia {
        let resolvedMedia = try await mediaStreamer.resolveMedia(item, requestContext: requestContext)
        return try await offlineStore.download(
            resolvedMedia,
            storageScope: storageScope,
            retentionPolicy: retentionPolicy,
            thumbnail: thumbnail,
            onProgress: onProgress
        )
    }

    public func enqueueDownload(
        _ item: WebMediaInfo,
        requestContext: WebMediaRequestContext = .init(),
        storageScope: WebMediaOfflineStorageScope,
        retentionPolicy: WebMediaRetentionPolicy? = nil,
        thumbnail: WebMediaThumbnailRequest = .automatic(),
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) async throws -> WebMediaDownloadRecord {
        let resolvedMedia = try await mediaStreamer.resolveMedia(item, requestContext: requestContext)
        return try await offlineStore.enqueueDownload(
            resolvedMedia,
            storageScope: storageScope,
            retentionPolicy: retentionPolicy,
            thumbnail: thumbnail,
            onProgress: onProgress
        )
    }

    public func waitForDownload(id: String) async throws -> StoredWebMedia {
        try await offlineStore.waitForDownload(id: id)
    }

    public func downloadEvents(id: String? = nil) async -> AsyncStream<WebMediaDownloadEvent> {
        await offlineStore.downloadEvents(id: id)
    }

    public func restorePendingDownloads(
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) async throws -> [WebMediaDownloadRecord] {
        try await offlineStore.restorePendingDownloads(onProgress: onProgress)
    }

    public func isDownloading(id: String) async throws -> Bool {
        try await offlineStore.isDownloading(id: id)
    }

    public func cancelDownload(id: String) async throws -> WebMediaDownloadRecord? {
        try await offlineStore.cancelDownload(id: id)
    }

    public func retryDownload(
        id: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void = { _ in }
    ) async throws -> WebMediaDownloadRecord {
        try await offlineStore.retryDownload(id: id, onProgress: onProgress)
    }

    public func downloadRecord(for item: WebMediaInfo) async throws -> WebMediaDownloadRecord? {
        try await offlineStore.downloadRecord(for: item)
    }

    public func currentDownloadRecord(id: String) async throws -> WebMediaDownloadRecord? {
        try await offlineStore.currentDownloadRecord(id: id)
    }

    public func allDownloadRecords(
        states: Set<WebMediaDownloadState>? = nil
    ) async throws -> [WebMediaDownloadRecord] {
        try await offlineStore.allDownloadRecords(states: states)
    }

    public func storedMedia(for item: WebMediaInfo) async throws -> StoredWebMedia? {
        try await offlineStore.storedMedia(for: item)
    }

    public func storedMedia(forPageURL pageURL: URL) async throws -> [StoredWebMedia] {
        try await offlineStore.storedMedia(forPageURL: pageURL)
    }

    public func bestStoredMedia(forPageURL pageURL: URL) async throws -> StoredWebMedia? {
        try await offlineStore.bestStoredMedia(forPageURL: pageURL)
    }

    public func storedMedia(id: String) async throws -> StoredWebMedia? {
        try await offlineStore.storedMedia(id: id)
    }

    public func ensureThumbnail(id: String) async throws -> StoredWebMedia? {
        try await offlineStore.ensureThumbnail(id: id)
    }

    public func allStoredMedia(scope: WebMediaOfflineStorageScope? = nil) async throws -> [StoredWebMedia] {
        try await offlineStore.allStoredMedia(scope: scope)
    }

    @discardableResult
    public func updateStorageScope(
        _ storageScope: WebMediaOfflineStorageScope,
        for id: String
    ) async throws -> StoredWebMedia {
        try await offlineStore.updateStorageScope(storageScope, for: id)
    }

    @discardableResult
    public func updateRetentionPolicy(
        _ retentionPolicy: WebMediaRetentionPolicy,
        for id: String
    ) async throws -> WebMediaDownloadRecord {
        try await offlineStore.updateRetentionPolicy(retentionPolicy, for: id)
    }

    public func deleteStoredMedia(id: String) async throws {
        try await offlineStore.deleteStoredMedia(id: id)
    }

    public func deleteAllStoredMedia(scope: WebMediaOfflineStorageScope? = nil) async throws {
        try await offlineStore.deleteAllStoredMedia(scope: scope)
    }

    public func purgeTransientMedia() async throws {
        try await offlineStore.purgeTransientMedia()
    }

    public func deleteTransientMedia(forPageURL pageURL: URL) async throws {
        try await offlineStore.deleteTransientMedia(forPageURL: pageURL)
    }

    public func purgeTransientMedia(exceptPageURLs pageURLs: [URL]) async throws {
        try await offlineStore.purgeTransientMedia(exceptPageURLs: pageURLs)
    }

    public func handlePageDidChange(from oldPageURL: URL?, to newPageURL: URL?) async throws {
        try await offlineStore.handlePageDidChange(from: oldPageURL, to: newPageURL)
    }

    public func handleSessionDidEnd() async throws {
        try await offlineStore.handleSessionDidEnd()
    }

    public func enforceTransientStoragePolicy() async throws {
        try await offlineStore.enforceTransientStoragePolicy()
    }

    public func enforceTransientStoragePolicy(exceptPageURLs pageURLs: [URL]) async throws {
        try await offlineStore.enforceTransientStoragePolicy(exceptPageURLs: pageURLs)
    }

    @discardableResult
    public func touchStoredMedia(id: String) async throws -> StoredWebMedia? {
        try await offlineStore.touchStoredMedia(id: id)
    }
}
