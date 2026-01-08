import Foundation
import CryptoKit

public struct AdblockListEndpoint: Sendable, Hashable {
    public var baseURL: URL
    public var path: String
    public var headers: [String: String]

    public init(baseURL: URL, path: String = "ios/latest.txt", headers: [String: String] = [:]) {
        self.baseURL = baseURL
        self.path = path
        self.headers = headers
    }

    public var url: URL {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(trimmedPath)
    }

    public static let braveDefault = AdblockListEndpoint(
        baseURL: URL(string: "https://adblock-data.s3.brave.com")!,
        path: "ios/latest.txt"
    )
}

public struct AdblockContentRulesResult: Sendable, Equatable {
    public let contentRules: AdblockContentRules
    public let rulesSourceHash: String

    public init(contentRules: AdblockContentRules, rulesSourceHash: String) {
        self.contentRules = contentRules
        self.rulesSourceHash = rulesSourceHash
    }
}

public enum AdblockRulesStoreError: Error {
    case invalidResponse
    case unexpectedStatus(Int)
    case missingCachedRules
    case invalidRulesData
}

public actor AdblockRulesStore {
    private struct CacheMetadata: Codable {
        var etag: String?
        var lastModified: String?
        var rulesHash: String?
        var lastFetchedAt: Date?
    }

    private struct CachedContentRules: Codable {
        var rulesJSON: String
        var truncated: Bool
        var sourceHash: String
        var updatedAt: Date
    }

    private let endpoint: AdblockListEndpoint
    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let urlSession: URLSession

    public init(
        endpoint: AdblockListEndpoint = .braveDefault,
        cacheDirectory: URL? = nil,
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.fileManager = fileManager
        self.urlSession = urlSession
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.cacheDirectory = base
                .appendingPathComponent("SwiftBrave", isDirectory: true)
                .appendingPathComponent("Adblock", isDirectory: true)
        }
    }

    public func loadCachedContentRules() -> AdblockContentRulesResult? {
        guard
            let cached = loadCachedContentRulesFile()
        else {
            return nil
        }
        let contentRules = AdblockContentRules(rulesJSON: cached.rulesJSON, truncated: cached.truncated)
        return AdblockContentRulesResult(contentRules: contentRules, rulesSourceHash: cached.sourceHash)
    }

    public func loadCachedFilterList() -> String? {
        loadRulesFile()
    }

    public func refreshContentRules() async throws -> AdblockContentRulesResult {
        try ensureCacheDirectory()

        let (rules, metadata) = try await fetchRulesIfNeeded()
        let rulesHash = sha256Hex(rules)

        if let cached = loadCachedContentRulesFile(), cached.sourceHash == rulesHash {
            let contentRules = AdblockContentRules(rulesJSON: cached.rulesJSON, truncated: cached.truncated)
            return AdblockContentRulesResult(contentRules: contentRules, rulesSourceHash: rulesHash)
        }

        let converted = try BraveAdblock.contentBlockerRules(fromFilterSet: rules)
        let cached = CachedContentRules(
            rulesJSON: converted.rulesJSON,
            truncated: converted.truncated,
            sourceHash: rulesHash,
            updatedAt: Date()
        )
        saveCachedContentRulesFile(cached)

        var updatedMetadata = metadata ?? CacheMetadata()
        updatedMetadata.rulesHash = rulesHash
        updatedMetadata.lastFetchedAt = Date()
        saveMetadata(updatedMetadata)

        return AdblockContentRulesResult(contentRules: converted, rulesSourceHash: rulesHash)
    }

    private func fetchRulesIfNeeded() async throws -> (String, CacheMetadata?) {
        let metadata = loadMetadata()
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "GET"
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let etag = metadata?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = metadata?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AdblockRulesStoreError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            guard let rules = String(data: data, encoding: .utf8) else {
                throw AdblockRulesStoreError.invalidRulesData
            }
            saveRulesFile(rules)
            var updatedMetadata = metadata ?? CacheMetadata()
            updatedMetadata.etag = http.value(forHTTPHeaderField: "ETag") ?? updatedMetadata.etag
            updatedMetadata.lastModified = http.value(forHTTPHeaderField: "Last-Modified") ?? updatedMetadata.lastModified
            saveMetadata(updatedMetadata)
            return (rules, updatedMetadata)
        case 304:
            guard let cachedRules = loadRulesFile() else {
                throw AdblockRulesStoreError.missingCachedRules
            }
            return (cachedRules, metadata)
        default:
            throw AdblockRulesStoreError.unexpectedStatus(http.statusCode)
        }
    }

    private func ensureCacheDirectory() throws {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    private func rulesFileURL() -> URL {
        cacheDirectory.appendingPathComponent("rules.txt")
    }

    private func metadataFileURL() -> URL {
        cacheDirectory.appendingPathComponent("metadata.json")
    }

    private func contentRulesFileURL() -> URL {
        cacheDirectory.appendingPathComponent("content_rules.json")
    }

    private func loadRulesFile() -> String? {
        let url = rulesFileURL()
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func saveRulesFile(_ rules: String) {
        let url = rulesFileURL()
        try? rules.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadMetadata() -> CacheMetadata? {
        let url = metadataFileURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheMetadata.self, from: data)
    }

    private func saveMetadata(_ metadata: CacheMetadata) {
        let url = metadataFileURL()
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func loadCachedContentRulesFile() -> CachedContentRules? {
        let url = contentRulesFileURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedContentRules.self, from: data)
    }

    private func saveCachedContentRulesFile(_ cached: CachedContentRules) {
        let url = contentRulesFileURL()
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
