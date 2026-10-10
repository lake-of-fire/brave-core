import AVFoundation
import Foundation

/// This is a small, movable local artifact. Apple's HLS package stays at the
/// URL supplied by AVAssetDownloadURLSession for its entire lifetime.
struct WebMediaNativeHLSReference: Codable, Hashable, Sendable {
    let identifier: String
    let transferIdentifier: String
    let asset: WebMediaHLSLocalReference
}

/// The ownership registry is populated only from native delegate locations.
/// A reference file alone can never grant deletion authority for another path.
enum WebMediaNativeHLSAssets {
    private static let registryLock = NSLock()

    static var transferRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WebMedia/HLSDownloads", isDirectory: true)
    }

    private struct Ownership: Codable {
        let sessionIdentifier: String
        let reference: WebMediaNativeHLSReference
        let nativeAssetRoot: WebMediaHLSLocalReference
    }

    private static var ownershipRoot: URL { transferRoot.appendingPathComponent(".native-assets", isDirectory: true) }

    static func recordDelegateLocation(_ location: URL, identifier: String, transferIdentifier: String) throws {
        registryLock.lock()
        defer { registryLock.unlock() }
        let reference = WebMediaNativeHLSReference(identifier: identifier, transferIdentifier: transferIdentifier,
                                                   asset: WebMediaHLSLocalReference(location))
        guard safeNativeURL(reference.asset) != nil, UUID(uuidString: transferIdentifier) != nil else {
            throw WebMediaOfflineStoreError.invalidResponse
        }
        let ownership = Ownership(sessionIdentifier: WebMediaHLSAssetDownloader.backgroundSessionIdentifier,
                                   reference: reference,
                                   nativeAssetRoot: WebMediaHLSLocalReference(location.deletingLastPathComponent()))
        try FileManager.default.createDirectory(at: ownershipRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(ownership).write(to: ownershipURL(transferIdentifier), options: .atomic)
    }

    static func resolve(_ reference: WebMediaNativeHLSReference, requirePlayable: Bool = true) -> URL? {
        registryLock.lock()
        defer { registryLock.unlock() }
        guard let ownership = readOwnership(reference.transferIdentifier), ownership.reference == reference,
              let url = safeNativeURL(reference.asset),
              url.deletingLastPathComponent().standardizedFileURL == ownership.nativeAssetRoot.url.standardizedFileURL.resolvingSymlinksInPath(),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        if requirePlayable, AVURLAsset(url: url).assetCache?.isPlayableOffline != true { return nil }
        return url
    }

    static func remove(identifier: String, transferIdentifier: String) throws {
        registryLock.lock()
        defer { registryLock.unlock() }
        guard let ownership = readOwnership(transferIdentifier), ownership.reference.identifier == identifier,
              let url = safeNativeURL(ownership.reference.asset),
              url.deletingLastPathComponent().standardizedFileURL == ownership.nativeAssetRoot.url.standardizedFileURL.resolvingSymlinksInPath() else { return }
        // AVFoundation may share a native package between independently created
        // tasks. A second registered owner keeps that package alive.
        let ownershipFiles = try FileManager.default.contentsOfDirectory(at: ownershipRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        // An unreadable ownership record cannot be treated as proof that no
        // other consumer still owns this native package.
        let otherOwners = try ownershipFiles
            .map { try JSONDecoder().decode(Ownership.self, from: Data(contentsOf: $0)) }
            .contains {
                $0.reference.transferIdentifier != transferIdentifier
                    && $0.reference.asset == ownership.reference.asset
                    && $0.sessionIdentifier == ownership.sessionIdentifier
            }
        if !otherOwners, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.removeItem(at: ownershipURL(transferIdentifier))
    }

    static func removeCompletedReferences(in directory: URL, identifier: String) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.pathExtension == "hlsref" {
            guard let data = try? Data(contentsOf: file),
                  let reference = try? JSONDecoder().decode(WebMediaNativeHLSReference.self, from: data),
                  reference.identifier == identifier,
                  file.lastPathComponent == "media-\(reference.transferIdentifier).hlsref" else { continue }
            try remove(identifier: identifier, transferIdentifier: reference.transferIdentifier)
        }
    }

    static func byteCount(identifier: String) throws -> Int64 {
        registryLock.lock()
        defer { registryLock.unlock() }
        guard FileManager.default.fileExists(atPath: ownershipRoot.path) else { return 0 }
        var nativeURLs = Set<URL>()
        for file in try FileManager.default.contentsOfDirectory(at: ownershipRoot, includingPropertiesForKeys: nil)
            where file.pathExtension == "json" {
            let ownership = try JSONDecoder().decode(Ownership.self, from: Data(contentsOf: file))
            guard ownership.reference.identifier == identifier,
                  ownership.sessionIdentifier == WebMediaHLSAssetDownloader.backgroundSessionIdentifier else { continue }
            guard let url = safeNativeURL(ownership.reference.asset),
                  url.deletingLastPathComponent().standardizedFileURL == ownership.nativeAssetRoot.url.standardizedFileURL.resolvingSymlinksInPath() else {
                throw WebMediaOfflineStoreError.invalidResponse
            }
            if FileManager.default.fileExists(atPath: url.path) { nativeURLs.insert(url) }
        }
        return try nativeURLs.reduce(Int64(0)) { total, url in
            let (sum, overflow) = total.addingReportingOverflow(try StoredWebMediaFileSystem.directorySize(at: url))
            return overflow ? Int64.max : sum
        }
    }

    private static func ownershipURL(_ transferIdentifier: String) -> URL {
        ownershipRoot.appendingPathComponent(transferIdentifier + ".json")
    }

    private static func readOwnership(_ transferIdentifier: String) -> Ownership? {
        guard UUID(uuidString: transferIdentifier) != nil,
              let data = try? Data(contentsOf: ownershipURL(transferIdentifier)),
              let ownership = try? JSONDecoder().decode(Ownership.self, from: data),
              ownership.reference.transferIdentifier == transferIdentifier,
              ownership.sessionIdentifier == WebMediaHLSAssetDownloader.backgroundSessionIdentifier else { return nil }
        return ownership
    }

    private static func safeNativeURL(_ reference: WebMediaHLSLocalReference) -> URL? {
        guard reference.isRelativeToApplication, !reference.path.isEmpty,
              !reference.path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else { return nil }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let url = reference.url.standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(home.path + "/Library/"), url.path != home.path else { return nil }
        return url
    }
}
