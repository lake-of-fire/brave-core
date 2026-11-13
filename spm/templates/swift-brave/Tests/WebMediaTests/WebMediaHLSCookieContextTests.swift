import AVFoundation
import Foundation
import XCTest
@testable import WebMedia

final class WebMediaHLSCookieContextTests: XCTestCase {
    func testScopedCookiesKeepTheirAttributesAndUsePublicUserAgentOptions() throws {
        guard #available(iOS 16.0, macOS 13.0, macCatalyst 16.0, *) else {
            XCTAssertThrowsError(try WebMediaHLSCookieContext.assetOptions(headers: ["User-Agent": "Reader"], cookieContext: nil))
            return
        }
        let cookie = try makeCookie(value: "secret", domain: ".example.test", path: "/media", secure: true)
        let hints = ["Referer": "https://example.test/"]
        let options = try XCTUnwrap(WebMediaHLSCookieContext.assetOptions(
            headers: hints.merging(["cOoKiE": "unrelated=must-not-forward", "User-Agent": "Reader"]) { _, new in new },
            cookieContext: .init([cookie]), nativeOptionalRequestHeaders: hints))
        let cookies = try XCTUnwrap(options[AVURLAssetHTTPCookiesKey] as? [HTTPCookie])
        XCTAssertEqual(cookies.count, 1)
        XCTAssertEqual(cookies[0].value, "secret")
        XCTAssertEqual(cookies[0].domain, ".example.test")
        XCTAssertEqual(cookies[0].path, "/media")
        XCTAssertTrue(cookies[0].isSecure)
        if #available(iOS 16.0, macOS 13.0, macCatalyst 16.0, *) {
            XCTAssertEqual(options[AVURLAssetHTTPUserAgentKey] as? String, "Reader")
        }
        XCTAssertEqual(options.count, 2)
    }

    func testRawCookieRequiresScopedContextAndExplicitEmptyContextRemovesIt() throws {
        let headers = ["Cookie": "legacy=1"]
        XCTAssertThrowsError(try WebMediaHLSCookieContext.assetOptions(headers: headers, cookieContext: nil))
        let scoped = try XCTUnwrap(WebMediaHLSCookieContext.assetOptions(headers: headers, cookieContext: .init([])))
        XCTAssertEqual((scoped[AVURLAssetHTTPCookiesKey] as? [HTTPCookie])?.count, 0)
        XCTAssertEqual(scoped.count, 1)
        XCTAssertNil(try WebMediaHLSCookieContext.assetOptions(headers: [:], cookieContext: nil))
    }

    func testOwnedHintsRemainOnDirectRequestsButAreOptionalForNativeAssets() throws {
        let hints = ["Accept": "application/vnd.apple.mpegurl", "Referer": "https://example.test/watch"]
        let source = media(headers: hints, optional: hints)
        let capture = WebMediaCaptureResolvedMedia(candidate: .init(source.mediaInfo), url: source.url,
            mimeType: source.mimeType, requestHeaders: source.requestHeaders,
            nativeOptionalRequestHeaders: source.nativeOptionalRequestHeaders, resolutionMethod: .direct)
        let request = WebMediaCaptureDownloader.makeRequest(for: capture)
        for (name, value) in hints { XCTAssertEqual(request.value(forHTTPHeaderField: name), value) }
        XCTAssertEqual(capture.nativeOptionalRequestHeaders, hints)
        XCTAssertNil(try WebMediaNativeAssetOptions.options(for: source))
        XCTAssertThrowsError(try WebMediaNativeAssetOptions.options(for: media(headers: hints)))
    }

    func testRequiredOverridesClearEvenSameValueOptionalHints() throws {
        let referer = "https://example.test/watch"
        let hints = ["Referer": referer]
        let context = WebMediaRequestContext(headers: hints, nativeOptionalRequestHeaders: hints)
        let replaced = context.addingRequiredHeaders(["rEfErEr": referer])
        XCTAssertTrue(replaced.nativeOptionalRequestHeaders.isEmpty)
        XCTAssertEqual(replaced.headers, ["rEfErEr": referer])
        XCTAssertThrowsError(try WebMediaNativeAssetOptions.options(for: media(headers: replaced.headers,
            optional: replaced.nativeOptionalRequestHeaders)))
        let named = WebMediaRequestContext(headers: hints, referer: URL(string: referer)!, nativeOptionalRequestHeaders: hints)
        XCTAssertTrue(named.nativeOptionalRequestHeaders.isEmpty)
        let changed = media(headers: ["Referer": "https://other.test/"], optional: hints)
        XCTAssertTrue(changed.nativeOptionalRequestHeaders.isEmpty)
        XCTAssertThrowsError(try WebMediaNativeAssetOptions.options(for: changed))
    }

    func testCredentialsAndUserAgentCannotBeDeclaredOptional() throws {
        for headers in [["Authorization": "Bearer private"], ["Cookie": "session=private"], ["User-Agent": "Reader"]] {
            let source = media(headers: headers, optional: headers)
            XCTAssertTrue(source.nativeOptionalRequestHeaders.isEmpty)
            if headers["User-Agent"] == nil {
                XCTAssertThrowsError(try WebMediaNativeAssetOptions.options(for: source))
            }
        }
        XCTAssertThrowsError(try WebMediaNativeAssetOptions.options(for:
            media(headers: ["User-Agent": "Reader", "user-agent": "Reader"]))) { error in
            XCTAssertEqual(error as? WebMediaNativeAssetOptionsError, .ambiguousUserAgent)
        }
    }

    func testOptionalitySurvivesSnapshotRoundTripAndLegacyDecodeIsRequired() throws {
        let hints = ["Referer": "https://example.test/watch"]
        let source = media(headers: hints, optional: hints)
        let encoded = try JSONEncoder().encode(ResolvedWebMediaSnapshot(media: source))
        let restored = try JSONDecoder().decode(ResolvedWebMediaSnapshot.self, from: encoded).makeResolvedMedia()
        XCTAssertEqual(restored, source)
        XCTAssertNil(try WebMediaNativeAssetOptions.options(for: restored))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "nativeOptionalRequestHeaders")
        let decoded = try JSONDecoder().decode(ResolvedWebMediaSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy)).makeResolvedMedia()
        XCTAssertEqual(decoded.requestHeaders, hints)
        XCTAssertTrue(decoded.nativeOptionalRequestHeaders.isEmpty)
        XCTAssertThrowsError(try WebMediaNativeAssetOptions.options(for: decoded))
        XCTAssertNotEqual(try WebMediaDownloadedArtifactReceipt.requestKey(for: source),
            try WebMediaDownloadedArtifactReceipt.requestKey(for: decoded))
        let cookie = try makeCookie(value: "private", domain: "example.test", path: "/", secure: true)
        XCTAssertNotEqual(try WebMediaHLSCookieContext([cookie]).requestKey(base: WebMediaDownloadedArtifactReceipt.requestKey(for: source)),
            try WebMediaHLSCookieContext([cookie]).requestKey(base: WebMediaDownloadedArtifactReceipt.requestKey(for: decoded)))
    }

    func testLocalArtifactDoesNotRequireRemoteHeaderSupport() throws {
        let local = media(headers: ["Authorization": "Bearer private", "Referer": "https://example.test/"],
            url: URL(fileURLWithPath: "/private/local-media.mov"))
        XCTAssertNil(try WebMediaNativeAssetOptions.options(for: local))
    }

    private func media(headers: [String: String], optional: [String: String] = [:], url: URL? = nil) -> ResolvedWebMedia {
        let item = WebMediaInfo(name: "Headers", src: "https://example.test/audio.m3u8",
            pageSrc: "https://example.test/watch", pageTitle: "Headers", mimeType: "application/vnd.apple.mpegurl",
            duration: 10, detected: true, tagId: "headers", isInvisible: false)
        return ResolvedWebMedia(mediaInfo: item, url: url ?? URL(string: item.src)!, mimeType: item.mimeType,
            requestHeaders: headers, nativeOptionalRequestHeaders: optional, resolutionMethod: .direct)
    }

    func testChangedCredentialsAndScopeCannotAttachToAnOldTransferIdentity() throws {
        let original = try makeCookie(value: "account-a", domain: "example.test", path: "/media", secure: true)
        let originalKey = try WebMediaHLSCookieContext([original]).requestKey(base: "resource")
        for cookie in [
            try makeCookie(value: "account-b", domain: "example.test", path: "/media", secure: true),
            try makeCookie(value: "account-a", domain: "cdn.example.test", path: "/media", secure: true),
            try makeCookie(value: "account-a", domain: "example.test", path: "/other", secure: true),
            try makeCookie(value: "account-a", domain: "example.test", path: "/media", secure: false)
        ] {
            XCTAssertNotEqual(try WebMediaHLSCookieContext([cookie]).requestKey(base: "resource"), originalKey)
        }
        XCTAssertEqual(try WebMediaHLSCookieContext([original]).requestKey(base: "resource"), originalKey)
        XCTAssertNotEqual(try WebMediaHLSCookieContext([original]).requestKey(base: "new-resource"), originalKey)
        XCTAssertNotEqual(try WebMediaHLSCookieContext([]).requestKey(base: "resource"), originalKey)
        XCTAssertEqual(originalKey.count, 64)
        XCTAssertFalse(originalKey.contains("account-a"))
    }

    func testCookiePrecedenceIsPartOfTheTransferIdentity() throws {
        let broad = try makeCookie(value: "broad", domain: "example.test", path: "/", secure: true)
        let narrow = try makeCookie(value: "narrow", domain: "example.test", path: "/media", secure: true)
        XCTAssertNotEqual(
            try WebMediaHLSCookieContext([broad, narrow]).requestKey(base: "resource"),
            try WebMediaHLSCookieContext([narrow, broad]).requestKey(base: "resource")
        )
    }

    private func makeCookie(value: String, domain: String, path: String, secure: Bool) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "session", .value: value, .domain: domain, .path: path
        ]
        if secure { properties[.secure] = "TRUE" }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }
}
