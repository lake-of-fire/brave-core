import Foundation
import XCTest
@testable import WebMedia

final class WebMediaHLSRecoveryTests: XCTestCase {
    func testChangedCookiesCannotBypassDownloaderValidationAfterStoreFailure() async throws {
        try await assertReopen(changedCookies: true)
    }

    func testSameCookiesReuseCompletedArtifactThroughDownloaderAfterStoreFailure() async throws {
        try await assertReopen(changedCookies: false)
    }

    private func assertReopen(changedCookies: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = WebMediaOfflineStore.Configuration(
            persistentRootURL: root.appendingPathComponent("persistent"),
            transientRootURL: root.appendingPathComponent("transient"), excludeFromBackup: false)
        let cookieA = try cookie("account-a")
        let initial = ReceiptValidatingHLSDownloader(context: .init([cookieA]))
        let first = WebMediaOfflineStore(configuration: configuration,
            downloader: WebMediaAssetDownloader(hlsDownloaderFactory: { initial }))
        let item = WebMediaInfo(name: "Recovery", src: "https://example.test/audio.m3u8",
            pageSrc: "https://example.test/watch", pageTitle: "Recovery",
            mimeType: "application/vnd.apple.mpegurl", duration: 10,
            detected: true, tagId: "recovery", isInvisible: false)
        let media = ResolvedWebMedia(mediaInfo: item, url: URL(string: item.src)!,
            mimeType: item.mimeType, resolutionMethod: .direct)
        try await WebMediaOfflineStoreTesting.$afterDownloadedArtifact.withValue({
            throw RecoveryFailure.postDownload
        }) {
            do {
                _ = try await first.download(media, storageScope: .transient, thumbnail: .none)
                XCTFail("Expected post-download failure")
            } catch RecoveryFailure.postDownload {}
        }
        let records = try await first.allDownloadRecords()
        let record = try XCTUnwrap(records.first)
        _ = try await first.cancelDownload(id: record.id) // join the first attempt
        let destinationValue = await initial.destination
        let destination = try XCTUnwrap(destinationValue)
        let receiptURL = destination.appendingPathComponent(".downloaded-artifact.json")
        let saved = try JSONDecoder().decode(WebMediaDownloadedArtifactReceipt.self,
                                             from: Data(contentsOf: receiptURL))
        XCTAssertTrue(saved.requiresDownloaderValidation)
        XCTAssertEqual(saved.requestKey, try WebMediaHLSCookieContext([cookieA]).requestKey(
            base: WebMediaDownloadedArtifactReceipt.requestKey(for: media)))
        XCTAssertNotEqual(saved.requestKey, try WebMediaDownloadedArtifactReceipt.requestKey(for: media))

        let currentCookie = try cookie(changedCookies ? "account-b" : "account-a")
        let current = ReceiptValidatingHLSDownloader(context: .init([currentCookie]))
        let reopened = WebMediaOfflineStore(configuration: configuration,
            downloader: WebMediaAssetDownloader(hlsDownloaderFactory: { current }))
        if changedCookies {
            do {
                _ = try await reopened.download(media, storageScope: .transient, thumbnail: .none)
                XCTFail("Old credential artifact must not bypass the current downloader")
            } catch RecoveryFailure.changedCredentials {}
            let stored = try await reopened.storedMedia(id: record.id)
            XCTAssertNil(stored)
        } else {
            let stored = try await reopened.download(media, storageScope: .transient, thumbnail: .none)
            XCTAssertEqual(try Data(contentsOf: stored.localMediaURL), Data("completed payload".utf8))
        }
        let entries = await current.entries
        let transfers = await current.transfers
        let reused = await current.reused
        let reopenedDestination = await current.destination
        XCTAssertEqual(entries, 1, "Store must delegate context-sensitive recovery")
        XCTAssertEqual(reopenedDestination, destination)
        XCTAssertEqual(transfers, 0, "Same-context completed bytes need no new transfer")
        XCTAssertEqual(reused, changedCookies ? 0 : 1)
        _ = try await reopened.cancelDownload(id: record.id)
    }

    func testOpaqueSniffedHLSReopenUsesContextOwnerWithoutAnotherHTTPProbe() async throws {
        for changedCookies in [false, true] {
            for legacyReceipt in [false, true] {
                try await assertOpaqueReopen(changedCookies: changedCookies, legacyReceipt: legacyReceipt)
            }
        }
    }

    private func assertOpaqueReopen(changedCookies: Bool, legacyReceipt: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = WebMediaOfflineStore.Configuration(
            persistentRootURL: root.appendingPathComponent("persistent"),
            transientRootURL: root.appendingPathComponent("transient"), excludeFromBackup: false)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RecoveryHTTPProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let initial = ReceiptValidatingHLSDownloader(context: .init([try cookie("account-a")]), nativeReference: true)
        let first = WebMediaOfflineStore(configuration: configuration,
            downloader: WebMediaAssetDownloader(urlSession: session, hlsDownloaderFactory: { initial }))
        let item = WebMediaInfo(name: "Opaque", src: "https://example.test/opaque",
            pageSrc: "https://example.test/watch", pageTitle: "Opaque",
            mimeType: "application/octet-stream", duration: 10,
            detected: true, tagId: "opaque", isInvisible: false)
        let media = ResolvedWebMedia(mediaInfo: item, url: URL(string: item.src)!,
            mimeType: item.mimeType, resolutionMethod: .direct)
        XCTAssertNotEqual(media.containerKind, .hls)
        let requestsBeforeInitial = RecoveryHTTPProtocol.requests.value
        try await WebMediaOfflineStoreTesting.$afterDownloadedArtifact.withValue({ throw RecoveryFailure.postDownload }) {
            do {
                _ = try await first.download(media, storageScope: .transient, thumbnail: .none)
                XCTFail("Expected failure after native-reference receipt publication")
            } catch RecoveryFailure.postDownload {}
        }
        let records = try await first.allDownloadRecords()
        let record = try XCTUnwrap(records.first)
        _ = try await first.cancelDownload(id: record.id)
        let destinationValue = await initial.destination
        let destination = try XCTUnwrap(destinationValue)
        let receiptURL = destination.appendingPathComponent(".downloaded-artifact.json")
        let saved = try JSONDecoder().decode(WebMediaDownloadedArtifactReceipt.self, from: Data(contentsOf: receiptURL))
        XCTAssertEqual(saved.recoveryOwner, .downloader)
        if legacyReceipt {
            // Simulate a completed receipt downgraded by the previous Store.
            try JSONEncoder().encode(WebMediaDownloadedArtifactReceipt(artifact: saved.artifact,
                requestKey: WebMediaDownloadedArtifactReceipt.requestKey(for: media)))
                .write(to: receiptURL, options: .atomic)
        }
        let requestsBeforeReopen = RecoveryHTTPProtocol.requests.value
        XCTAssertEqual(requestsBeforeReopen, requestsBeforeInitial + 1,
                       "Initial opaque response must traverse the actual HTTP sniff path")
        let current = ReceiptValidatingHLSDownloader(
            context: .init([try cookie(changedCookies ? "account-b" : "account-a")]), nativeReference: true)
        let reopened = WebMediaOfflineStore(configuration: configuration,
            downloader: WebMediaAssetDownloader(urlSession: session, hlsDownloaderFactory: { current }))
        try await WebMediaOfflineStoreTesting.$afterDownloadedArtifact.withValue({ throw RecoveryFailure.postDownload }) {
            do {
                _ = try await reopened.download(media, storageScope: .transient, thumbnail: .none)
                XCTFail("Fixture intentionally stops before native playability validation")
            } catch RecoveryFailure.changedCredentials {
                XCTAssertTrue(changedCookies)
            } catch RecoveryFailure.postDownload {
                XCTAssertFalse(changedCookies)
            }
        }
        _ = try await reopened.cancelDownload(id: record.id)
        let entries = await current.entries
        let reused = await current.reused
        let transfers = await current.transfers
        let currentDestination = await current.destination
        XCTAssertEqual(entries, 1)
        XCTAssertEqual(currentDestination, destination)
        XCTAssertEqual(reused, changedCookies ? 0 : 1)
        XCTAssertEqual(transfers, 0)
        XCTAssertEqual(RecoveryHTTPProtocol.requests.value, requestsBeforeReopen,
                       "Retained sniffed HLS must reach its owner without another HTTP request")
    }

    func testGenericPreparedFileRecoveryStillAvoidsAnotherDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = WebMediaOfflineStore.Configuration(
            persistentRootURL: root.appendingPathComponent("persistent"),
            transientRootURL: root.appendingPathComponent("transient"), excludeFromBackup: false)
        let initial = PreparedFileDownloader()
        let first = WebMediaOfflineStore(configuration: configuration, downloader: initial)
        let item = WebMediaInfo(name: "File", src: "https://example.test/audio.mp3",
            pageSrc: "https://example.test/watch", pageTitle: "File", mimeType: "audio/mpeg",
            duration: 10, detected: true, tagId: "file", isInvisible: false)
        let media = ResolvedWebMedia(mediaInfo: item, url: URL(string: item.src)!,
            mimeType: item.mimeType, resolutionMethod: .direct)
        try await WebMediaOfflineStoreTesting.$afterDownloadedArtifact.withValue({ throw RecoveryFailure.postDownload }) {
            do {
                _ = try await first.download(media, storageScope: .transient, thumbnail: .none)
                XCTFail("Expected post-download failure")
            } catch RecoveryFailure.postDownload {}
        }
        let records = try await first.allDownloadRecords()
        let record = try XCTUnwrap(records.first)
        _ = try await first.cancelDownload(id: record.id)
        let current = PreparedFileDownloader()
        let reopened = WebMediaOfflineStore(configuration: configuration, downloader: current)
        let stored = try await reopened.download(media, storageScope: .transient, thumbnail: .none)
        XCTAssertEqual(try Data(contentsOf: stored.localMediaURL), Data("generic payload".utf8))
        let calls = await current.calls
        XCTAssertEqual(calls, 0)
        _ = try await reopened.cancelDownload(id: record.id)
    }

    func testLegacyNativeReceiptCannotUseGenericStoreRecovery() {
        let receipt = WebMediaDownloadedArtifactReceipt(
            artifact: .init(relativeMediaPath: "media-token.hlsref", mimeType: nil, byteCount: 1),
            requestKey: "old-unscoped-base-key")
        XCTAssertTrue(receipt.requiresDownloaderValidation)
    }

    private func cookie(_ value: String) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [
            .name: "session", .value: value, .domain: "example.test", .path: "/"
        ]))
    }
}

private enum RecoveryFailure: Error { case postDownload, changedCredentials }

/// Exercises actual Store persistence and actual AssetDownloader dispatch while
/// replacing AVFoundation transport with a deterministic context validator.
/// A regular file permits real Store payload validation without claiming a
/// playable native HLS package or an OS background transfer.
private actor ReceiptValidatingHLSDownloader: WebMediaHLSAssetDownloading {
    let context: WebMediaHLSCookieContext
    let nativeReference: Bool
    private(set) var entries = 0
    private(set) var transfers = 0
    private(set) var reused = 0
    private(set) var destination: URL?

    init(context: WebMediaHLSCookieContext, nativeReference: Bool = false) {
        self.context = context
        self.nativeReference = nativeReference
    }

    func download(media: ResolvedWebMedia, into directory: URL, identifier: String,
                  onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void) async throws -> DownloadedWebMediaArtifact {
        entries += 1
        destination = directory
        let requestKey = try context.requestKey(base: WebMediaDownloadedArtifactReceipt.requestKey(for: media))
        let receiptURL = directory.appendingPathComponent(".downloaded-artifact.json")
        if let data = try? Data(contentsOf: receiptURL) {
            let receipt = try JSONDecoder().decode(WebMediaDownloadedArtifactReceipt.self, from: data)
            let recordedKey: String
            if nativeReference {
                recordedKey = try String(contentsOf: directory.appendingPathComponent(".fixture-hls-key"), encoding: .utf8)
            } else {
                recordedKey = receipt.requestKey
            }
            guard recordedKey == requestKey else { throw RecoveryFailure.changedCredentials }
            reused += 1
            return receipt.artifact
        }
        transfers += 1
        let payload = Data("completed payload".utf8)
        let artifact = DownloadedWebMediaArtifact(relativeMediaPath: nativeReference ? "media-fixture.hlsref" : "prepared.bin",
            mimeType: "application/octet-stream", byteCount: Int64(payload.count))
        try payload.write(to: directory.appendingPathComponent(artifact.relativeMediaPath))
        if nativeReference {
            // Models the independent context-scoped coordinator journal. The
            // Store's receipt is not the context owner's source of authority.
            try requestKey.write(to: directory.appendingPathComponent(".fixture-hls-key"), atomically: true, encoding: .utf8)
        }
        try JSONEncoder().encode(WebMediaDownloadedArtifactReceipt(
            artifact: artifact, requestKey: requestKey, recoveryOwner: .downloader,
            baseRequestKey: WebMediaDownloadedArtifactReceipt.requestKey(for: media)))
            .write(to: receiptURL, options: .atomic)
        return artifact
    }
}

private final class RecoveryHTTPRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class RecoveryHTTPProtocol: URLProtocol {
    static let requests = RecoveryHTTPRequests()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.increment()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/octet-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("#EXTM3U\n#EXT-X-VERSION:3\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor PreparedFileDownloader: WebMediaArtifactDownloading {
    private(set) var calls = 0
    func download(media: ResolvedWebMedia, into directory: URL, identifier: String,
                  onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void) async throws -> DownloadedWebMediaArtifact {
        calls += 1
        let bytes = Data("generic payload".utf8)
        try bytes.write(to: directory.appendingPathComponent("prepared.mp3"))
        return .init(relativeMediaPath: "prepared.mp3", mimeType: "audio/mpeg", byteCount: Int64(bytes.count))
    }
}
