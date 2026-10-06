import AVFoundation
import Foundation
import UniformTypeIdentifiers

public struct WebMediaMimeTypeDetector {
    public let mimeType: String?
    public let fileExtension: String?

    public init(url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension.isEmpty == false {
            self.fileExtension = fileExtension
            self.mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType
        } else {
            self.fileExtension = nil
            self.mimeType = nil
        }
    }

    public init(mimeType: String?) {
        guard let mimeType else {
            self.mimeType = nil
            self.fileExtension = nil
            return
        }

        let normalizedMimeType = mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        self.mimeType = normalizedMimeType
        self.fileExtension = normalizedMimeType.flatMap { mimeType in
            if mimeType == "application/vnd.apple.mpegurl" || mimeType == "application/x-mpegurl" {
                return "movpkg"
            }
            return UTType(mimeType: mimeType)?.preferredFilenameExtension
        }
    }

    public init(data: Data) {
        if Self.findHeader(offset: 0, in: data, header: [0x1A, 0x45, 0xDF, 0xA3]) {
            mimeType = "video/webm"
            fileExtension = "webm"
            return
        }

        if Self.findHeader(offset: 0, in: data, header: [0x4F, 0x67, 0x67, 0x53]) {
            mimeType = "application/ogg"
            fileExtension = "ogg"
            return
        }

        if Self.findHeader(offset: 0, in: data, header: [0x52, 0x49, 0x46, 0x46])
            && Self.findHeader(offset: 8, in: data, header: [0x57, 0x41, 0x56, 0x45]) {
            mimeType = "audio/x-wav"
            fileExtension = "wav"
            return
        }

        if Self.findHeader(offset: 0, in: data, header: [0xFF, 0xFB])
            || Self.findHeader(offset: 0, in: data, header: [0x49, 0x44, 0x33]) {
            mimeType = "audio/mpeg"
            fileExtension = "mp3"
            return
        }

        if Self.findHeader(offset: 0, in: data, header: [0x66, 0x4C, 0x61, 0x43]) {
            mimeType = "audio/flac"
            fileExtension = "flac"
            return
        }

        if Self.findHeader(offset: 4, in: data, header: [0x66, 0x74, 0x79, 0x70]) {
            mimeType = "video/mp4"
            fileExtension = "mp4"
            return
        }

        if Self.findHeader(offset: 0, in: data, header: [0x46, 0x4C, 0x56, 0x01]) {
            mimeType = "video/x-flv"
            fileExtension = "flv"
            return
        }

        mimeType = nil
        fileExtension = nil
    }

    public static func preferredFileExtension(
        url: URL?,
        mimeType: String?,
        leadingData: Data? = nil,
        fallback: String
    ) -> String {
        if let mimeTypeExtension = WebMediaMimeTypeDetector(mimeType: mimeType).fileExtension {
            return mimeTypeExtension
        }
        if let url, let urlExtension = WebMediaMimeTypeDetector(url: url).fileExtension {
            return urlExtension
        }
        if let leadingData, let dataExtension = WebMediaMimeTypeDetector(data: leadingData).fileExtension {
            return dataExtension
        }
        return fallback
    }

    public static func supportedAVAssetMIMETypes() -> [String] {
        AVURLAsset.audiovisualTypes().compactMap { UTType($0.rawValue)?.preferredMIMEType }
    }

    private static func findHeader(offset: Int, in data: Data, header: [UInt8]) -> Bool {
        guard offset >= 0, data.count >= offset + header.count else {
            return false
        }

        return [UInt8](data[offset..<(offset + header.count)]) == header
    }
}
