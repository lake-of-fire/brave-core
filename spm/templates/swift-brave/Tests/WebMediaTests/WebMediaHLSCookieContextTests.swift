import AVFoundation
import Foundation
import XCTest
@testable import WebMedia

final class WebMediaHLSCookieContextTests: XCTestCase {
    func testScopedCookiesKeepTheirAttributesAndReplaceOnlyTheRawCookieHeader() throws {
        let cookie = try makeCookie(value: "secret", domain: ".example.test", path: "/media", secure: true)
        let options = try XCTUnwrap(WebMediaHLSCookieContext.assetOptions(
            headers: ["cOoKiE": "unrelated=must-not-forward", "User-Agent": "Reader", "Referer": "https://example.test/"],
            cookieContext: .init([cookie])
        ))
        let cookies = try XCTUnwrap(options[AVURLAssetHTTPCookiesKey] as? [HTTPCookie])
        XCTAssertEqual(cookies.count, 1)
        XCTAssertEqual(cookies[0].value, "secret")
        XCTAssertEqual(cookies[0].domain, ".example.test")
        XCTAssertEqual(cookies[0].path, "/media")
        XCTAssertTrue(cookies[0].isSecure)
        let headers = try XCTUnwrap(options["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String])
        XCTAssertEqual(headers, ["User-Agent": "Reader", "Referer": "https://example.test/"])
    }

    func testAbsentContextPreservesLegacyOptionsButExplicitEmptyContextRemovesRawCookies() throws {
        let headers = ["Cookie": "legacy=1"]
        let legacy = try XCTUnwrap(WebMediaHLSCookieContext.assetOptions(headers: headers, cookieContext: nil))
        XCTAssertEqual(legacy["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String], headers)
        XCTAssertNil(legacy[AVURLAssetHTTPCookiesKey])
        let scoped = try XCTUnwrap(WebMediaHLSCookieContext.assetOptions(headers: headers, cookieContext: .init([])))
        XCTAssertEqual((scoped[AVURLAssetHTTPCookiesKey] as? [HTTPCookie])?.count, 0)
        XCTAssertNil(scoped["AVURLAssetHTTPHeaderFieldsKey"])
        XCTAssertNil(WebMediaHLSCookieContext.assetOptions(headers: [:], cookieContext: nil))
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
