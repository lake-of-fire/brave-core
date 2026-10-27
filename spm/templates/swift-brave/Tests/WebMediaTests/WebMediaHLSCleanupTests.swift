import AVFoundation
import Foundation
import XCTest
@testable import WebMedia

final class WebMediaHLSCleanupTests: XCTestCase {
    func testDeletingPrivateStorePreservesSameResourceTransferInAnotherStore() async throws {
        let captured = HLSDiscardRecorder()
        try await WebMediaOfflineStoreTesting.$discardHLSArtifacts.withValue({ captured.record($0) }) {
            try await withStores { first, second, firstDownloader, secondDownloader, _, _ in
                let media = makeMedia()
                let firstRecord = try await first.enqueueDownload(media, storageScope: .transient, thumbnail: .none)
                let secondRecord = try await second.enqueueDownload(media, storageScope: .transient, thumbnail: .none)
                XCTAssertEqual(firstRecord.id, secondRecord.id)
                try await waitUntil {
                    let firstStarted = await firstDownloader.started
                    let secondStarted = await secondDownloader.started
                    return firstStarted && secondStarted
                }
                let firstDestinationValue = await firstDownloader.destination
                let secondDestinationValue = await secondDownloader.destination
                let firstDestination = try XCTUnwrap(firstDestinationValue)
                let secondDestination = try XCTUnwrap(secondDestinationValue)

                _ = try await first.cancelDownload(id: firstRecord.id)
                try await first.deleteStoredMedia(id: firstRecord.id)
                let scope = try XCTUnwrap(captured.scopes.last)
                // This is the exact command predicate used by the coordinator
                // before cancelling a task or removing a durable transfer.
                XCTAssertTrue(scope.contains(identifier: firstRecord.id, destination: .init(firstDestination)))
                XCTAssertFalse(scope.contains(identifier: secondRecord.id, destination: .init(secondDestination)))
                let firstCancelled = await firstDownloader.cancelled
                let secondCancelled = await secondDownloader.cancelled
                let secondIsDownloading = try await second.isDownloading(id: secondRecord.id)
                XCTAssertTrue(firstCancelled)
                XCTAssertFalse(secondCancelled)
                XCTAssertTrue(secondIsDownloading)
            }
        }
    }

    func testCompletedNativeReferenceDeletionPreservesOtherRegisteredOwner() async throws {
        let captured = HLSDiscardRecorder()
        try await WebMediaOfflineStoreTesting.$discardHLSArtifacts.withValue({ captured.record($0) }) {
            try await withStores { first, second, _, _, firstRoot, secondRoot in
                let identifier = UUID().uuidString
                let firstToken = UUID().uuidString
                let secondToken = UUID().uuidString
                let nativeRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("WebMediaCleanupTest-\(UUID().uuidString)", isDirectory: true)
                let package = nativeRoot.appendingPathComponent("media.movpkg", isDirectory: true)
                try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
                try Data("owned native segment".utf8).write(to: package.appendingPathComponent("segment.ts"))
                defer {
                    try? WebMediaNativeHLSAssets.remove(identifier: identifier, transferIdentifier: firstToken)
                    try? WebMediaNativeHLSAssets.remove(identifier: identifier, transferIdentifier: secondToken)
                    try? FileManager.default.removeItem(at: nativeRoot)
                }
                try WebMediaNativeHLSAssets.recordDelegateLocation(package, identifier: identifier, transferIdentifier: firstToken)
                try WebMediaNativeHLSAssets.recordDelegateLocation(package, identifier: identifier, transferIdentifier: secondToken)
                let firstReference = WebMediaNativeHLSReference(identifier: identifier, transferIdentifier: firstToken, asset: .init(package))
                let secondReference = WebMediaNativeHLSReference(identifier: identifier, transferIdentifier: secondToken, asset: .init(package))
                try writeReference(firstReference, root: firstRoot)
                try writeReference(secondReference, root: secondRoot)

                // Explicit deletion also handles a reference whose metadata is
                // damaged/missing; native deletion still requires its registry.
                try await first.deleteStoredMedia(id: identifier)
                XCTAssertNil(WebMediaNativeHLSAssets.resolve(firstReference, requirePlayable: false))
                XCTAssertEqual(WebMediaNativeHLSAssets.resolve(secondReference, requirePlayable: false), package.standardizedFileURL.resolvingSymlinksInPath())
                XCTAssertTrue(FileManager.default.fileExists(atPath: package.path))
                let firstScope = try XCTUnwrap(captured.scopes.last)
                XCTAssertFalse(firstScope.contains(identifier: identifier, destination: .init(secondRoot)))

                try await second.deleteStoredMedia(id: identifier)
                XCTAssertFalse(FileManager.default.fileExists(atPath: package.path))
                XCTAssertNil(WebMediaNativeHLSAssets.resolve(secondReference, requirePlayable: false))
            }
        }
    }

    func testScopeMatchesBothOwnedRootsButRejectsSiblingPrefixAndDifferentResource() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hls-store")
        let persistent = root.appendingPathComponent("persistent")
        let transient = root.appendingPathComponent("transient")
        let scope = WebMediaHLSDiscardScope(identifier: "resource", rootDirectories: [persistent, transient])
        XCTAssertTrue(scope.contains(identifier: "resource", destination: .init(persistent.appendingPathComponent(".download-attempts/resource/attempt"))))
        XCTAssertTrue(scope.contains(identifier: "resource", destination: .init(transient.appendingPathComponent(".download-attempts/resource/attempt"))))
        XCTAssertFalse(scope.contains(identifier: "other", destination: .init(transient)))
        XCTAssertFalse(scope.contains(identifier: "resource", destination: .init(root.appendingPathComponent("transient-other/.download-attempts/resource/attempt"))))
    }

    func testBulkScopeCleanupDoesNotAuthorizeAnotherStoresAttempt() async throws {
        let captured = HLSDiscardRecorder()
        try await WebMediaOfflineStoreTesting.$discardHLSArtifacts.withValue({ captured.record($0) }) {
            try await withStores { first, _, _, _, firstRoot, secondRoot in
                let identifier = "orphan-resource"
                let attemptRoot = firstRoot.appendingPathComponent(".download-attempts/\(identifier)/attempt")
                try FileManager.default.createDirectory(at: attemptRoot, withIntermediateDirectories: true)
                try await first.deleteAllStoredMedia(scope: .transient)
                let scope = try XCTUnwrap(captured.scopes.last)
                XCTAssertTrue(scope.contains(identifier: identifier, destination: .init(attemptRoot)))
                XCTAssertFalse(scope.contains(identifier: identifier, destination: .init(secondRoot.appendingPathComponent(".download-attempts/\(identifier)/attempt"))))
            }
        }
    }

    private func makeMedia() -> ResolvedWebMedia {
        let item = WebMediaInfo(name: "Same HLS resource", src: "https://media.example.test/audio.m3u8",
                               pageSrc: "https://example.test/watch", pageTitle: "Shared resource",
                               mimeType: "application/vnd.apple.mpegurl", duration: 10,
                               detected: true, tagId: "same-resource", isInvisible: false)
        return ResolvedWebMedia(mediaInfo: item, url: URL(string: item.src)!, mimeType: item.mimeType,
                                resolutionMethod: .direct)
    }

    private func writeReference(_ reference: WebMediaNativeHLSReference, root: URL) throws {
        let directory = root.appendingPathComponent(reference.identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(reference).write(to: directory.appendingPathComponent("media-\(reference.transferIdentifier).hlsref"))
    }

    private func withStores(
        _ operation: (WebMediaOfflineStore, WebMediaOfflineStore, SuspendedHLSTestDownloader,
                      SuspendedHLSTestDownloader, URL, URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HLSCleanup-\(UUID().uuidString)")
        let firstRoot = root.appendingPathComponent("first/transient")
        let secondRoot = root.appendingPathComponent("second/transient")
        let firstDownloader = SuspendedHLSTestDownloader()
        let secondDownloader = SuspendedHLSTestDownloader()
        let first = WebMediaOfflineStore(configuration: .init(
            persistentRootURL: root.appendingPathComponent("first/persistent"), transientRootURL: firstRoot,
            excludeFromBackup: false), downloader: firstDownloader)
        let second = WebMediaOfflineStore(configuration: .init(
            persistentRootURL: root.appendingPathComponent("second/persistent"), transientRootURL: secondRoot,
            excludeFromBackup: false), downloader: secondDownloader)
        do {
            try await operation(first, second, firstDownloader, secondDownloader, firstRoot, secondRoot)
        } catch {
            await cleanup(first)
            await cleanup(second)
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        await cleanup(first)
        await cleanup(second)
        try? FileManager.default.removeItem(at: root)
    }

    private func cleanup(_ store: WebMediaOfflineStore) async {
        for record in (try? await store.allDownloadRecords()) ?? [] {
            _ = try? await store.cancelDownload(id: record.id)
            try? await store.deleteStoredMedia(id: record.id)
        }
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private final class HLSDiscardRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [WebMediaHLSDiscardScope] = []
    var scopes: [WebMediaHLSDiscardScope] { lock.withLock { values } }
    func record(_ scope: WebMediaHLSDiscardScope) { lock.withLock { values.append(scope) } }
}

private actor SuspendedHLSTestDownloader: WebMediaArtifactDownloading {
    private(set) var started = false
    private(set) var cancelled = false
    private(set) var destination: URL?

    func download(media: ResolvedWebMedia, into directory: URL, identifier: String,
                  onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void) async throws -> DownloadedWebMediaArtifact {
        destination = directory
        started = true
        do {
            try await Task.sleep(for: .seconds(60))
            throw URLError(.timedOut)
        } catch {
            cancelled = Task.isCancelled
            throw error
        }
    }
}
