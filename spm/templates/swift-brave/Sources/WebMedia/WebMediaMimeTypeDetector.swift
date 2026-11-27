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
        if let prefix = Self.decodeBoundedUTF8Prefix(
            data.prefix(4096),
            reachedProbeLimit: data.count >= 4096
        )?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))),
           prefix.hasPrefix("#EXTM3U") {
            mimeType = "application/vnd.apple.mpegurl"
            fileExtension = "movpkg"
            return
        }

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

    private static func decodeBoundedUTF8Prefix(
        _ data: Data.SubSequence,
        reachedProbeLimit: Bool
    ) -> String? {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        guard reachedProbeLimit else { return nil }

        // The probe is capped at 4 KB and may stop inside an otherwise valid
        // multibyte scalar. Ignore only a valid, incomplete scalar at that
        // exact boundary. Malformed UTF-8 elsewhere and short payloads remain rejected.
        let bytes = [UInt8](data)
        let lowerBound = max(0, bytes.count - 4)
        for start in stride(from: bytes.count - 1, through: lowerBound, by: -1) {
            let lead = bytes[start]
            let expectedLength: Int
            switch lead {
            case 0xC2...0xDF: expectedLength = 2
            case 0xE0...0xEF: expectedLength = 3
            case 0xF0...0xF4: expectedLength = 4
            default: continue
            }

            let suffixLength = bytes.count - start
            guard suffixLength < expectedLength,
                  bytes[(start + 1)...].allSatisfy({ (0x80...0xBF).contains($0) })
            else { continue }

            if expectedLength >= 3, suffixLength >= 2 {
                let continuation = bytes[start + 1]
                if (lead == 0xE0 && continuation < 0xA0)
                    || (lead == 0xED && continuation > 0x9F)
                    || (lead == 0xF0 && continuation < 0x90)
                    || (lead == 0xF4 && continuation > 0x8F) {
                    continue
                }
            }

            return String(data: Data(bytes[..<start]), encoding: .utf8)
        }
        return nil
    }
}
