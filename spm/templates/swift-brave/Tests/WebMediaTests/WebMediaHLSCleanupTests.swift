import AVFoundation
import Foundation
import XCTest
@testable import WebMedia

final class WebMediaHLSCleanupTests: XCTestCase {
    func testCancellationJoinsActiveProducerBeforeReturningMissingMetadata() async throws {
        try await assertCancellationWithLostMetadata(corrupt: false)
    }

    func testCancellationJoinsActiveProducerBeforeThrowingCorruptMetadata() async throws {
        try await assertCancellationWithLostMetadata(corrupt: true)
    }

    private func assertCancellationWithLostMetadata(corrupt: Bool) async throws {
        let captured = HLSDiscardRecorder()
        try await WebMediaOfflineStoreTesting.$discardHLSArtifacts.withValue({ captured.record($0) }) {
            try await withStores { store, _, downloader, _, root, _ in
                await downloader.holdCancellation()
                let media = makeMedia()
                let record = try await store.enqueueDownload(media, storageScope: .transient, thumbnail: .none)
                try await waitUntil { await downloader.started }
                let previousDestination = await downloader.destination
                let metadata = root.appendingPathComponent(record.id).appendingPathComponent("metadata.json")
                let corruptBytes = Data("{invalid-json".utf8)
                if corrupt { try corruptBytes.write(to: metadata, options: .atomic) }
                else { try FileManager.default.removeItem(at: metadata) }

                let completion = HLSCancellationCompletion()
                let cancellation = Task { () -> Result<WebMediaDownloadRecord?, Error> in
                    let result: Result<WebMediaDownloadRecord?, Error>
                    do { result = .success(try await store.cancelDownload(id: record.id)) }
                    catch { result = .failure(error) }
                    await completion.markCompleted()
                    return result
                }
                do {
                    try await waitUntil { await downloader.cancelled }
                    let returnedBeforeProducerExit = await completion.completed
                    XCTAssertFalse(returnedBeforeProducerExit)
                } catch {
                    await downloader.releaseCancellation()
                    _ = await cancellation.value
                    throw error
                }
                await downloader.releaseCancellation()
                let result = await cancellation.value
                let producerFinished = await downloader.finished
                XCTAssertTrue(producerFinished)
                switch result {
                case .success(let current):
                    XCTAssertFalse(corrupt, "Corrupt metadata must remain an error after producer shutdown")
                    XCTAssertNil(current)
                case .failure(let error):
                    XCTAssertTrue(corrupt, "Missing metadata should return nil only after joining the producer")
                    XCTAssertTrue(error is DecodingError)
                }
                if corrupt { XCTAssertEqual(try Data(contentsOf: metadata), corruptBytes) }
                else { XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.path)) }

                // Metadata loss does not authorize guessed reconstruction.
                // Explicitly remove this store's damaged slot before a fresh
                // same-resource attempt; old task teardown cannot retire it.
                try await store.deleteStoredMedia(id: record.id)
                await downloader.prepareForNextAttempt()
                let replacement = try await store.enqueueDownload(media, storageScope: .transient, thumbnail: .none)
                XCTAssertEqual(replacement.id, record.id)
                try await waitUntil { await downloader.started }
                let replacementDestination = await downloader.destination
                XCTAssertNotEqual(replacementDestination, previousDestination)
                let replacementIsDownloading = try await store.isDownloading(id: replacement.id)
                XCTAssertTrue(replacementIsDownloading)
                let cancelledReplacement = try await store.cancelDownload(id: replacement.id)
                XCTAssertEqual(cancelledReplacement?.state, .cancelled)
                let replacementFinished = await downloader.finished
                XCTAssertTrue(replacementFinished)
            }
        }
    }

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
            await cleanup(first, downloader: firstDownloader)
            await cleanup(second, downloader: secondDownloader)
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        await cleanup(first, downloader: firstDownloader)
        await cleanup(second, downloader: secondDownloader)
        try? FileManager.default.removeItem(at: root)
    }

    private func cleanup(_ store: WebMediaOfflineStore, downloader: SuspendedHLSTestDownloader) async {
        await downloader.releaseCancellation()
        if let identifier = await downloader.identifier {
            _ = try? await store.cancelDownload(id: identifier)
            try? await store.deleteStoredMedia(id: identifier)
        }
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
    private(set) var identifier: String?
    private(set) var finished = false
    private var cancellationReleased = true
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func holdCancellation() { cancellationReleased = false }

    func releaseCancellation() {
        cancellationReleased = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func prepareForNextAttempt() {
        started = false
        cancelled = false
        finished = false
        destination = nil
        identifier = nil
    }

    func download(media: ResolvedWebMedia, into directory: URL, identifier: String,
                  onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void) async throws -> DownloadedWebMediaArtifact {
        destination = directory
        self.identifier = identifier
        started = true
        do {
            try await Task.sleep(for: .seconds(60))
            throw URLError(.timedOut)
        } catch {
            cancelled = Task.isCancelled
            if !cancellationReleased {
                await withCheckedContinuation { cancellationWaiters.append($0) }
            }
            finished = true
            throw error
        }
    }
}

private actor HLSCancellationCompletion {
    private(set) var completed = false
    func markCompleted() { completed = true }
}
