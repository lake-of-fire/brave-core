import AVFoundation
import CryptoKit
import Foundation

/// One background session survives downloader instances and process launches.
/// The coordinator persists its task/attempt mapping before starting network I/O.
public final class WebMediaHLSAssetDownloader: NSObject, WebMediaHLSAssetDownloading, @unchecked Sendable {
    public static let backgroundSessionIdentifier =
        "\(Bundle.main.bundleIdentifier ?? "com.lakeoffire.swift-brave").webmedia.hls.v1"

    public func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        try await WebMediaHLSDownloadCoordinator.shared.download(
            media: media, into: directory, identifier: identifier, onProgress: onProgress
        )
    }

    /// Forward UIApplicationDelegate's background URL-session callback here.
    /// The completion is delivered on the main queue after durable delegate work.
    @discardableResult
    public static func handleEvents(
        forBackgroundURLSession identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) -> Bool {
        guard identifier == backgroundSessionIdentifier else { return false }
        WebMediaHLSDownloadCoordinator.shared.handleEvents(completionHandler: completionHandler)
        return true
    }

    public static func reconnectBackgroundDownloads() {
        WebMediaHLSDownloadCoordinator.shared.reconnect()
    }

    static func acknowledgeArtifact(in directory: URL) {
        WebMediaHLSDownloadCoordinator.shared.acknowledgeArtifact(in: directory)
    }

    static func discardArtifacts(identifier: String) {
        WebMediaHLSDownloadCoordinator.shared.discardArtifacts(identifier: identifier)
    }
}

struct WebMediaHLSLocalReference: Codable, Hashable, Sendable {
    let path: String
    let isRelativeToApplication: Bool

    init(_ url: URL) {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        let absolute = url.standardizedFileURL.resolvingSymlinksInPath().path
        isRelativeToApplication = absolute.hasPrefix(home + "/")
        path = isRelativeToApplication ? String(absolute.dropFirst(home.count + 1)) : absolute
    }

    var url: URL {
        isRelativeToApplication
            ? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(path)
            : URL(fileURLWithPath: path)
    }
}

private final class WebMediaHLSDownloadCoordinator: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    static let shared = WebMediaHLSDownloadCoordinator()

    private enum Phase: String, Codable, Sendable { case prepared, running, received, published, failed, cancelled }

    private struct Record: Codable, Sendable {
        let key: String
        let sessionIdentifier: String
        let identifier: String
        let destination: WebMediaHLSLocalReference
        let requestKey: String
        var token: String
        var taskIdentifier: Int?
        var phase: Phase
        var location: WebMediaHLSLocalReference?
        var artifact: DownloadedWebMediaArtifact?
        var failureDescription: String?
    }

    // These fields are used only on stateQueue, including the cancellation latch.
    private final class Request: @unchecked Sendable {
        let id = UUID()
        var key: String?
        var cancelled = false
        var finished = false
        var continuation: CheckedContinuation<DownloadedWebMediaArtifact, Error>?
        let onProgress: @Sendable (WebMediaDownloadProgress) -> Void

        init(onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void) {
            self.onProgress = onProgress
        }
    }

    private let stateQueue = DispatchQueue(label: "com.lakeoffire.webmedia.hls-lifecycle")
    private let manifestRoot = WebMediaNativeHLSAssets.transferRoot
    private var session: AVAssetDownloadURLSession?
    private var records: [String: Record] = [:]
    private var tasks: [String: AVAssetDownloadTask] = [:]
    private var requests: [String: [UUID: Request]] = [:]
    private var reconciling = false
    private var afterReconciliation: [() -> Void] = []
    private var afterCancellation: [String: [() -> Void]] = [:]
    private var backgroundCompletions: [@Sendable () -> Void] = []

    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        let request = Request(onProgress: onProgress)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                stateQueue.async {
                    request.continuation = continuation
                    guard !request.cancelled else {
                        self.finish(request, with: .failure(CancellationError()))
                        return
                    }
                    do {
                        try self.ensureSession()
                        let start = { self.startOrAttach(request, media: media, directory: directory, identifier: identifier) }
                        if self.reconciling { self.afterReconciliation.append(start) } else { start() }
                    } catch {
                        self.finish(request, with: .failure(error))
                    }
                }
            }
        } onCancel: {
            self.stateQueue.async { self.cancel(request) }
        }
    }

    func reconnect() {
        stateQueue.async { try? self.ensureSession() }
    }

    func handleEvents(completionHandler: @escaping @Sendable () -> Void) {
        stateQueue.async {
            self.backgroundCompletions.append(completionHandler)
            do {
                try self.ensureSession()
            } catch {
                // Registration failure must not strand the application's launch
                // completion. The unreadable manifests remain available to retry.
                self.finishBackgroundEvents()
            }
        }
    }

    func acknowledgeArtifact(in directory: URL) {
        let destination = WebMediaHLSLocalReference(directory)
        stateQueue.async {
            for (key, record) in self.records where record.destination == destination
                && self.tasks[key] == nil && self.requests[key]?.isEmpty != false {
                self.records.removeValue(forKey: key)
                try? FileManager.default.removeItem(at: self.manifestURL(for: key))
            }
        }
    }

    func discardArtifacts(identifier: String) {
        stateQueue.async {
            do {
                try self.ensureSession()
                let discard = { self.discardOwnedTransfers(identifier: identifier) }
                if self.reconciling { self.afterReconciliation.append(discard) } else { discard() }
            } catch {
                // Leave both journal and asset intact if ownership cannot be
                // loaded. No guessed path is ever used for native deletion.
            }
        }
    }

    private func discardOwnedTransfers(identifier: String) {
        for (key, var record) in records where record.identifier == identifier {
            finishRequests(key, with: .failure(CancellationError()))
            if let task = tasks[key] {
                record.phase = .cancelled
                records[key] = record
                try? persist(record)
                task.cancel()
            } else {
                do {
                    try WebMediaNativeHLSAssets.remove(identifier: identifier, transferIdentifier: record.token)
                    records.removeValue(forKey: key)
                    try? FileManager.default.removeItem(at: manifestURL(for: key))
                } catch { }
            }
        }
    }

    private func ensureSession() throws {
        guard session == nil else { return }
        try FileManager.default.createDirectory(at: manifestRoot, withIntermediateDirectories: true)
        for file in try FileManager.default.contentsOfDirectory(at: manifestRoot,
                                                                 includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])
            where file.pathExtension == "json" {
            // A damaged journal is retained; it cannot authorize adopting an
            // unrelated task. Healthy transfers still reconnect independently.
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  record.sessionIdentifier == WebMediaHLSAssetDownloader.backgroundSessionIdentifier,
                  file.deletingPathExtension().lastPathComponent == record.key else { continue }
            records[record.key] = record
        }
        let configuration = URLSessionConfiguration.background(
            withIdentifier: WebMediaHLSAssetDownloader.backgroundSessionIdentifier
        )
        configuration.isDiscretionary = false
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = AVAssetDownloadURLSession(configuration: configuration,
                                                assetDownloadDelegate: self, delegateQueue: delegateQueue)
        self.session = session
        reconciling = true
        session.getAllTasks { allTasks in
            self.stateQueue.async {
                guard self.session === session else { return }
                for task in allTasks {
                    guard let task = task as? AVAssetDownloadTask,
                          let entry = self.records.first(where: {
                              $0.value.taskIdentifier == task.taskIdentifier
                                  && task.taskDescription == $0.value.token
                          }),
                          entry.value.phase == .running || entry.value.phase == .prepared || entry.value.phase == .cancelled else {
                        // This session is exclusively ours. An unmapped task
                        // cannot produce an artifact with defensible ownership.
                        task.cancel()
                        continue
                    }
                    self.tasks[entry.key] = task
                    if !FileManager.default.fileExists(atPath: entry.value.destination.url.path) {
                        var abandoned = entry.value
                        abandoned.phase = .cancelled
                        self.records[entry.key] = abandoned
                        try? self.persist(abandoned)
                        task.cancel()
                    } else if entry.value.phase == .cancelled { task.cancel() }
                    else if task.state == .suspended { task.resume() }
                }
                for (key, record) in self.records
                    where !FileManager.default.fileExists(atPath: record.destination.url.path) && self.tasks[key] == nil {
                    if (try? WebMediaNativeHLSAssets.remove(identifier: record.identifier, transferIdentifier: record.token)) != nil {
                        self.records.removeValue(forKey: key)
                        try? FileManager.default.removeItem(at: self.manifestURL(for: key))
                    }
                }
                self.reconciling = false
                let actions = self.afterReconciliation
                self.afterReconciliation.removeAll()
                actions.forEach { $0() }
            }
        }
    }

    private func startOrAttach(_ request: Request, media: ResolvedWebMedia, directory: URL, identifier: String) {
        guard !request.finished else { return }
        guard !request.cancelled else { finish(request, with: .failure(CancellationError())); return }
        guard session != nil else { finish(request, with: .failure(WebMediaOfflineStoreError.downloadFailed)); return }
        do {
            let destination = WebMediaHLSLocalReference(directory)
            let key = Self.digest(identifier + "\u{1F}" + destination.path)
            let requestKey = try WebMediaDownloadedArtifactReceipt.requestKey(for: media)
            request.key = key
            requests[key, default: [:]][request.id] = request
            if let record = records[key], record.phase == .cancelled {
                if tasks[key] != nil {
                    afterCancellation[key, default: []].append {
                        self.startOrAttach(request, media: media, directory: directory, identifier: identifier)
                    }
                    return
                }
                try WebMediaNativeHLSAssets.remove(identifier: record.identifier, transferIdentifier: record.token)
            }
            if let record = records[key], record.requestKey == requestKey {
                if record.phase == .published, let artifact = record.artifact,
                   Self.payloadExists(artifact, in: directory, identifier: record.identifier) {
                    finishRequests(key, with: .success(artifact))
                    return
                }
                if tasks[key] == nil, record.phase == .running || record.phase == .prepared,
                   let location = record.location,
                   WebMediaNativeHLSAssets.resolve(.init(identifier: record.identifier,
                       transferIdentifier: record.token, asset: location)) != nil {
                    // The OS may finish while the process is absent, leaving
                    // no live task to reattach. Its registered package and
                    // offline cache prove that reference publication can resume.
                    var received = record
                    received.phase = .received
                    try persist(received)
                    try publish(received)
                    return
                }
                if record.phase == .received,
                   record.location.map({ FileManager.default.fileExists(atPath: $0.url.path) }) == true
                    || (record.phase == .received && FileManager.default.fileExists(
                        atPath: directory.appendingPathComponent("media-\(record.token).hlsref").path)) {
                    try publish(record)
                    return
                }
                if let task = tasks[key], record.phase == .running {
                    if task.state == .suspended { task.resume() }
                    return
                }
            }
            // A fresh generation never reuses an old task's callback token or
            // output filename. A changed URL/header representation starts over.
            if tasks[key] != nil {
                requests[key]?.removeValue(forKey: request.id)
                finish(request, with: .failure(WebMediaOfflineStoreError.downloadInProgress))
                return
            }
            if let previous = records[key] {
                try WebMediaNativeHLSAssets.remove(identifier: previous.identifier, transferIdentifier: previous.token)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var record = Record(key: key,
                                sessionIdentifier: WebMediaHLSAssetDownloader.backgroundSessionIdentifier,
                                identifier: identifier, destination: destination, requestKey: requestKey,
                                token: UUID().uuidString, taskIdentifier: nil, phase: .prepared)
            try persist(record)
            let options = media.requestHeaders.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": media.requestHeaders]
            let asset = AVURLAsset(url: media.url, options: options)
            guard let task = session?.makeAssetDownloadTask(asset: asset,
                                                            assetTitle: media.mediaInfo.preferredDisplayName,
                                                            assetArtworkData: nil, options: nil) else {
                throw WebMediaOfflineStoreError.downloadFailed
            }
            task.taskDescription = record.token
            record.taskIdentifier = task.taskIdentifier
            record.phase = .running
            do { try persist(record) } catch { task.cancel(); throw error }
            tasks[key] = task
            task.resume()
        } catch {
            if let key = request.key { finishRequests(key, with: .failure(error)) }
            else { finish(request, with: .failure(error)) }
        }
    }

    private func cancel(_ request: Request) {
        guard !request.finished else { return }
        request.cancelled = true
        if let key = request.key {
            requests[key]?.removeValue(forKey: request.id)
            if requests[key]?.isEmpty != false {
                requests.removeValue(forKey: key)
                if var record = records[key], record.phase != .published {
                    record.phase = .cancelled
                    records[key] = record
                    try? persist(record)
                    tasks[key]?.cancel()
                }
            }
        }
        // A cancellation arriving before registration leaves a latch; only a
        // registered continuation may complete, and each can complete once.
        if request.continuation != nil { finish(request, with: .failure(CancellationError())) }
    }

    private func finish(_ request: Request, with result: Result<DownloadedWebMediaArtifact, Error>) {
        guard !request.finished, let continuation = request.continuation else { return }
        request.finished = true
        request.continuation = nil
        continuation.resume(with: result)
    }

    private func finishRequests(_ key: String, with result: Result<DownloadedWebMediaArtifact, Error>) {
        let waiting = requests.removeValue(forKey: key) ?? [:]
        for request in waiting.values { finish(request, with: result) }
    }

    private func ownedRecord(_ session: URLSession, _ task: URLSessionTask) -> Record? {
        guard self.session === session else { return nil }
        return records.values.first {
            $0.taskIdentifier == task.taskIdentifier && $0.token == task.taskDescription
                && ($0.phase == .running || $0.phase == .prepared || $0.phase == .received || $0.phase == .cancelled)
        }
    }

    private func manifestURL(for key: String) -> URL { manifestRoot.appendingPathComponent(key + ".json") }

    private func persist(_ record: Record) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: manifestURL(for: record.key), options: .atomic)
        records[record.key] = record
        // Kept next to the attempt so storage restoration knows it must retain
        // the exact directory to which the background task was originally bound.
        if FileManager.default.fileExists(atPath: record.destination.url.path) {
            try data.write(to: record.destination.url.appendingPathComponent(".hls-transfer.json"), options: .atomic)
        }
    }

    private func rememberLocation(_ location: URL, session: URLSession, task: AVAssetDownloadTask) {
        stateQueue.async {
            guard var record = self.ownedRecord(session, task) else { return }
            record.location = WebMediaHLSLocalReference(location)
            do {
                try WebMediaNativeHLSAssets.recordDelegateLocation(location, identifier: record.identifier,
                                                                    transferIdentifier: record.token)
                try self.persist(record)
            }
            catch {
                // Keep the task/token attached until cancellation finishes.
                // A late native location still belongs to this generation and
                // must be registered and reclaimed before a retry can start.
                record.phase = .cancelled
                self.records[record.key] = record
                try? self.persist(record)
                self.tasks[record.key]?.cancel()
                self.finishRequests(record.key, with: .failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        rememberLocation(location, session: session, task: assetDownloadTask)
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        rememberLocation(location, session: session, task: assetDownloadTask)
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        let expected = timeRangeExpectedToLoad.duration.seconds
        let loaded = loadedTimeRanges.map(\.timeRangeValue.duration.seconds).reduce(0, +)
        let fraction = expected.isFinite && loaded.isFinite && expected > 0 ? max(0, min(1, loaded / expected)) : 0
        stateQueue.async {
            guard let record = self.ownedRecord(session, assetDownloadTask), record.phase == .running else { return }
            let progress = WebMediaDownloadProgress(id: record.identifier, fractionCompleted: fraction,
                                                     bytesDownloaded: 0, totalBytesExpected: nil)
            for request in self.requests[record.key]?.values ?? Dictionary<UUID, Request>().values {
                if !request.finished { request.onProgress(progress) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            guard var record = self.ownedRecord(session, task) else { return }
            self.tasks.removeValue(forKey: record.key)
            do {
                if record.phase == .cancelled {
                    try WebMediaNativeHLSAssets.remove(identifier: record.identifier, transferIdentifier: record.token)
                    self.records.removeValue(forKey: record.key)
                    try? FileManager.default.removeItem(at: self.manifestURL(for: record.key))
                    let waiting = self.afterCancellation.removeValue(forKey: record.key) ?? []
                    waiting.forEach { $0() }
                    return
                }
                if let error {
                    record.phase = .failed
                    record.failureDescription = error.localizedDescription
                    try self.persist(record)
                    self.finishRequests(record.key, with: .failure(error))
                } else {
                    // Persist network success separately from publication. A
                    // relaunch can finish reference publication interrupted midway.
                    record.phase = .received
                    try self.persist(record)
                    try self.publish(record)
                }
            } catch {
                self.afterCancellation.removeValue(forKey: record.key)
                self.finishRequests(record.key, with: .failure(error))
            }
        }
    }

    private func publish(_ record: Record) throws {
        let directory = record.destination.url
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw WebMediaOfflineStoreError.mediaNotFound
        }
        guard let location = record.location else { throw WebMediaOfflineStoreError.downloadNotFinished }
        let reference = WebMediaNativeHLSReference(identifier: record.identifier,
                                                   transferIdentifier: record.token, asset: location)
        guard let nativeURL = WebMediaNativeHLSAssets.resolve(reference) else {
            throw WebMediaOfflineStoreError.downloadNotFinished
        }
        let byteCount = try StoredWebMediaFileSystem.directorySize(at: nativeURL)
        guard byteCount > 0 else { throw WebMediaOfflineStoreError.downloadNotFinished }
        let relativePath = "media-\(record.token).hlsref"
        // The only published file is our reference. Never relocate Apple's
        // private asset package or treat it as a normal URLSession temp file.
        try JSONEncoder().encode(reference).write(to: directory.appendingPathComponent(relativePath), options: .atomic)
        let artifact = DownloadedWebMediaArtifact(relativeMediaPath: relativePath,
                                                   mimeType: "application/vnd.apple.mpegurl", byteCount: byteCount)
        var completed = record
        completed.phase = .published
        completed.artifact = artifact
        try persist(completed)
        // The store can finish a download even if the process died after this
        // callback and before its suspended continuation resumed.
        try JSONEncoder().encode(WebMediaDownloadedArtifactReceipt(artifact: artifact, requestKey: record.requestKey))
            .write(to: directory.appendingPathComponent(".downloaded-artifact.json"), options: .atomic)
        let progress = WebMediaDownloadProgress(id: record.identifier, fractionCompleted: 1,
                                                 bytesDownloaded: byteCount, totalBytesExpected: byteCount)
        for request in requests[record.key]?.values ?? Dictionary<UUID, Request>().values {
            if !request.finished { request.onProgress(progress) }
        }
        finishRequests(record.key, with: .success(artifact))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        stateQueue.async {
            guard self.session === session else { return }
            self.finishBackgroundEvents()
        }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        stateQueue.async {
            guard self.session === session else { return }
            self.session = nil
            self.tasks.removeAll()
            self.reconciling = false
            self.afterCancellation.removeAll()
            let failure = error ?? WebMediaOfflineStoreError.downloadFailed
            for key in Array(self.requests.keys) { self.finishRequests(key, with: .failure(failure)) }
            let pending = self.afterReconciliation
            self.afterReconciliation.removeAll()
            pending.forEach { $0() }
            // Keep journals intact so the next launch/attempt can reconnect or
            // finish an already received artifact instead of losing its owner.
            self.finishBackgroundEvents()
        }
    }

    private func finishBackgroundEvents() {
        let completions = backgroundCompletions
        backgroundCompletions.removeAll()
        for completion in completions { DispatchQueue.main.async(execute: completion) }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func payloadExists(_ artifact: DownloadedWebMediaArtifact, in directory: URL, identifier: String) -> Bool {
        StoredWebMediaFileSystem.validatedPayloadURL(relativePath: artifact.relativeMediaPath,
            rootDirectory: directory, expectedByteCount: artifact.byteCount, expectedOwnerIdentifier: identifier) != nil
    }
}
