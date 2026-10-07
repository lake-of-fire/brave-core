import XCTest
import CryptoKit
@testable import WebMedia

final class WebMediaTests: XCTestCase {
    func testWebMediaInfoDecodesAndNormalizesRelativeURL() throws {
        let body: [String: Any] = [
            "name": "Example",
            "src": "/video/master.m3u8",
            "pageSrc": "https://example.com/watch?v=1",
            "pageTitle": "Example Page",
            "mimeType": "video/mp4",
            "duration": 12.5,
            "detected": true,
            "tagId": "tag-1",
            "invisible": false,
        ]

        let info = try XCTUnwrap(WebMediaInfo.decode(from: body))
        XCTAssertEqual(info.src, "https://example.com/video/master.m3u8")
        XCTAssertEqual(info.kind, .video)
        XCTAssertFalse(info.isInvisible)
    }

    func testWebMediaInfoNormalizesProtocolRelativeURL() {
        let info = WebMediaInfo(
            name: "Example",
            src: "//cdn.example.com/audio.mp3",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Example Page",
            mimeType: "audio/mpeg",
            duration: 12.5,
            detected: true,
            tagId: "tag-1",
            isInvisible: false
        )

        XCTAssertEqual(info.src, "https://cdn.example.com/audio.mp3")
        XCTAssertEqual(info.kind, .audio)
        XCTAssertTrue(info.isHTTPSource)
    }

    func testWebMediaInfoTreatsM3U8AsHLSContainer() {
        let info = WebMediaInfo(
            name: "Stream",
            src: "https://cdn.example.com/master.m3u8",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Example Page",
            mimeType: "application/x-mpegURL",
            duration: 12.5,
            detected: true,
            tagId: "tag-1",
            isInvisible: false
        )

        XCTAssertEqual(info.containerKind, .hls)
        XCTAssertEqual(info.kind, .unknown)
    }

    func testWebMediaInfoDerivesAudioOnlyPlaybackKindForHLSAudioStream() {
        let info = WebMediaInfo(
            name: "Podcast audio stream",
            src: "https://cdn.example.com/audio/master.m3u8",
            pageSrc: "https://example.com/listen",
            pageTitle: "Podcast episode",
            mimeType: "application/vnd.apple.mpegurl",
            duration: 600,
            detected: true,
            tagId: "audio-hls",
            isInvisible: false
        )

        XCTAssertEqual(info.playbackKind, .audioOnly)
        XCTAssertTrue(info.isLikelyAudioOnly)
    }

    func testMessageDecoderRejectsWrongSecurityToken() {
        let body: [String: Any] = [
            "securityToken": "wrong",
            "state": "interactive",
        ]

        XCTAssertNil(
            WebMediaScriptMessageDecoder.decode(
                body: body,
                expectingSecurityToken: "expected"
            )
        )
    }

    func testPlaybackEventDecoderNormalizesCurrentSourceAndPresentationMode() throws {
        let body: [String: Any] = [
            "securityToken": "expected-token",
            "messageKind": "playback",
            "eventName": "playing",
            "tagId": "player-1",
            "pageSrc": "https://example.com/watch?v=1#fragment",
            "pageTitle": "Example Page",
            "src": "/video/master.m3u8",
            "currentSrc": "//cdn.example.com/video/master.m3u8#time=10",
            "mimeType": "application/vnd.apple.mpegurl",
            "mediaType": "video",
            "currentTime": 12.5,
            "duration": 120.0,
            "paused": false,
            "ended": false,
            "playbackRate": 1.0,
            "muted": false,
            "volume": 0.75,
            "readyState": 4,
            "networkState": 2,
            "presentationMode": "picture-in-picture",
            "isInvisible": false,
        ]

        let decoded = try XCTUnwrap(
            WebMediaScriptMessageDecoder.decode(
                body: body,
                expectingSecurityToken: "expected-token"
            )
        )

        guard case .playback(let event) = decoded else {
            return XCTFail("Expected playback event")
        }

        XCTAssertEqual(event.eventName, .playing)
        XCTAssertEqual(event.snapshot.src, "https://example.com/video/master.m3u8")
        XCTAssertEqual(event.snapshot.currentSrc, "https://cdn.example.com/video/master.m3u8#time=10")
        XCTAssertEqual(event.snapshot.pageLookupKey, "https://example.com/watch?v=1")
        XCTAssertEqual(event.snapshot.presentationMode, .pictureInPicture)
        XCTAssertEqual(event.snapshot.mediaType, .video)
    }

    func testScriptSetBuildsExpectedHandlerNames() throws {
        let configuration = WebMediaScriptConfiguration(
            messageHandlerName: "mediaHandler",
            securityToken: "security-token",
            namespaceToken: "namespace"
        )

        let scripts = try WebMediaScriptEngine.makeScriptSet(configuration: configuration)

        XCTAssertTrue(scripts.detectorSource.contains("const SECURITY_TOKEN = 'security-token';"))
        XCTAssertTrue(scripts.detectorSource.contains("mediaHandler"))
        XCTAssertTrue(scripts.detectorSource.contains("webMediaProcessDocumentLoad_namespace"))
        XCTAssertTrue(scripts.detectorSource.contains("mediaCurrentTimeFromTag_namespace"))
        XCTAssertTrue(scripts.detectorSource.contains("webMediaTelemetryAttached_namespace"))
        XCTAssertTrue(scripts.detectorSource.contains("window.webkit.messageHandlers"))
        XCTAssertFalse(scripts.detectorSource.contains("playlistProcessDocumentLoad"))
        XCTAssertFalse(scripts.detectorSource.contains("playlistLongPressed"))
        XCTAssertFalse(scripts.detectorSource.contains("includeOnce(\"Playlist\""))
        XCTAssertTrue(scripts.firefoxShimSource.contains("window.__firefox__"))
        XCTAssertTrue(scripts.mediaSourceOverrideSource.contains("delete window.MediaSource;"))
    }

    func testWebMediaScriptsBuildExpectedUserScripts() throws {
        let scriptSet = try WebMediaScripts.make(
            messageHandlerName: "mediaHandler",
            allowedDomains: ["youtube.com"],
            configuration: WebMediaScriptConfiguration(
                messageHandlerName: "mediaHandler",
                securityToken: "security-token",
                namespaceToken: "namespace"
            )
        )

        XCTAssertEqual(scriptSet.messageHandlerName, "mediaHandler")
        XCTAssertEqual(scriptSet.userScripts.count, 3)
        XCTAssertEqual(scriptSet.userScripts.first?.allowedDomains, ["youtube.com"])
        XCTAssertTrue(scriptSet.userScripts[2].source.contains("mediaHandler"))
        XCTAssertTrue(scriptSet.userScripts[2].source.contains("security-token"))
        XCTAssertEqual(
            scriptSet.processDocumentLoadJavaScript,
            "window.__firefox__.webMediaProcessDocumentLoad_namespace()"
        )
    }

    func testWebMediaMessageDecoderUsesSecurityToken() throws {
        let scriptSet = try WebMediaScripts.make(
            messageHandlerName: "mediaHandler",
            configuration: WebMediaScriptConfiguration(
                messageHandlerName: "mediaHandler",
                securityToken: "expected-token",
                namespaceToken: "namespace"
            )
        )

        let body: [String: Any] = [
            "securityToken": "expected-token",
            "state": "interactive",
        ]

        let decoded = WebMediaMessageDecoder.decode(body: body, scriptSet: scriptSet)
        XCTAssertEqual(decoded, .readyState(.init(state: "interactive")))
    }

    func testWebMediaMessageDecoderDecodesPlaybackEvents() throws {
        let scriptSet = try WebMediaScripts.make(
            messageHandlerName: "mediaHandler",
            configuration: WebMediaScriptConfiguration(
                messageHandlerName: "mediaHandler",
                securityToken: "expected-token",
                namespaceToken: "namespace"
            )
        )

        let body: [String: Any] = [
            "securityToken": "expected-token",
            "messageKind": "playback",
            "eventName": "heartbeat",
            "tagId": "player-1",
            "pageSrc": "https://example.com/watch?v=1",
            "pageTitle": "Example Page",
            "src": "https://cdn.example.com/audio.m4a",
            "currentSrc": "https://cdn.example.com/audio.m4a",
            "mimeType": "audio/mp4",
            "mediaType": "audio",
            "currentTime": 45.0,
            "duration": 300.0,
            "paused": false,
            "ended": false,
            "playbackRate": 1.0,
            "muted": false,
            "volume": 1.0,
            "readyState": 4,
            "networkState": 1,
            "presentationMode": "inline",
            "isInvisible": false,
        ]

        let decoded = WebMediaMessageDecoder.decode(body: body, scriptSet: scriptSet)
        XCTAssertEqual(
            decoded,
            .playback(
                WebMediaPlaybackEvent(
                    eventName: .heartbeat,
                    snapshot: WebMediaPlaybackSnapshot(
                        tagId: "player-1",
                        pageSrc: "https://example.com/watch?v=1",
                        pageTitle: "Example Page",
                        src: "https://cdn.example.com/audio.m4a",
                        currentSrc: "https://cdn.example.com/audio.m4a",
                        mimeType: "audio/mp4",
                        mediaType: .audio,
                        currentTime: 45.0,
                        duration: 300.0,
                        paused: false,
                        ended: false,
                        playbackRate: 1.0,
                        muted: false,
                        volume: 1.0,
                        readyState: 4,
                        networkState: 1,
                        presentationMode: .inline,
                        isInvisible: false
                    )
                )
            )
        )
    }

    func testWebMediaCandidateSelectorPrefersVisibleDirectAudio() {
        let invisibleVideo = WebMediaInfo(
            name: "Video",
            src: "https://example.com/video.mp4",
            pageSrc: "https://example.com/watch",
            pageTitle: "Watch",
            mimeType: "video/mp4",
            duration: 100,
            detected: true,
            tagId: "video",
            isInvisible: true
        )
        let visibleAudio = WebMediaInfo(
            name: "Audio",
            src: "https://example.com/audio.m4a",
            pageSrc: "https://example.com/watch",
            pageTitle: "Watch",
            mimeType: "audio/mp4",
            duration: 30,
            detected: true,
            tagId: "audio",
            isInvisible: false
        )

        let preferred = WebMediaCandidateSelector.preferredCandidate(
            from: [invisibleVideo, visibleAudio]
        )

        XCTAssertEqual(preferred?.tagId, "audio")
    }

    func testMediaCaptureCandidateSelectorUsesNeutralSurface() {
        let invisibleVideo = WebMediaCaptureCandidate(
            name: "Video",
            sourceURL: URL(string: "https://example.com/video.mp4"),
            pageURL: URL(string: "https://example.com/watch"),
            pageTitle: "Watch",
            mimeType: "video/mp4",
            duration: 100,
            detected: true,
            tagID: "video",
            isInvisible: true
        )
        let visibleAudio = WebMediaCaptureCandidate(
            name: "Audio",
            sourceURL: URL(string: "https://example.com/audio.m4a"),
            pageURL: URL(string: "https://example.com/watch"),
            pageTitle: "Watch",
            mimeType: "audio/mp4",
            duration: 30,
            detected: true,
            tagID: "audio",
            isInvisible: false
        )

        let preferred = WebMediaCaptureCandidateSelector.preferredCandidate(
            from: [invisibleVideo, visibleAudio]
        )

        XCTAssertEqual(preferred?.tagID, "audio")
        XCTAssertEqual(preferred?.preferredDisplayName, "Audio")
    }

    func testMediaCaptureMessageDecoderWrapsCandidateMessage() throws {
        let scriptSet = try WebMediaCaptureWebScripts.make(
            messageHandlerName: "mediaHandler",
            configuration: WebMediaCaptureScriptConfiguration(
                messageHandlerName: "mediaHandler",
                securityToken: "expected-token",
                namespaceToken: "namespace"
            )
        )

        let body: [String: Any] = [
            "securityToken": "expected-token",
            "name": "Example",
            "src": "/video/master.m3u8",
            "pageSrc": "https://example.com/watch?v=1",
            "pageTitle": "Example Page",
            "mimeType": "video/mp4",
            "duration": 12.5,
            "detected": true,
            "tagId": "tag-1",
            "invisible": false,
        ]

        let decoded = try XCTUnwrap(WebMediaCaptureMessageDecoder.decode(body: body, scriptSet: scriptSet))
        guard case .candidate(let candidate) = decoded else {
            return XCTFail("Expected candidate message")
        }

        XCTAssertEqual(candidate.tagID, "tag-1")
        XCTAssertEqual(candidate.pageURL?.absoluteString, "https://example.com/watch?v=1")
        XCTAssertEqual(candidate.sourceURL?.absoluteString, "https://example.com/video/master.m3u8")
    }

    func testWebMediaCandidateSelectorPrefersAudioOnlyHLSOverVideoHLS() {
        let audioStream = WebMediaInfo(
            name: "Audio stream",
            src: "https://example.com/audio/master.m3u8",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode audio",
            mimeType: "application/vnd.apple.mpegurl",
            duration: 1800,
            detected: true,
            tagId: "audio-hls",
            isInvisible: false
        )
        let videoStream = WebMediaInfo(
            name: "Video stream",
            src: "https://example.com/video/master.m3u8",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode video",
            mimeType: "application/vnd.apple.mpegurl",
            duration: 1800,
            detected: true,
            tagId: "video-hls",
            isInvisible: false
        )

        let preferred = WebMediaCandidateSelector.preferredCandidate(
            from: [videoStream, audioStream]
        )

        XCTAssertEqual(preferred?.tagId, "audio-hls")
    }

    func testWebMediaCandidateSelectorPrefersRefreshedDirectURLForSameTag() {
        let staleBlob = WebMediaInfo(
            name: "Episode",
            src: "blob:https://example.com/123",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode",
            mimeType: "",
            duration: 1800,
            detected: true,
            tagId: "episode-player",
            isInvisible: false
        )
        let refreshedDirect = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode",
            mimeType: "audio/mp4",
            duration: 1800,
            detected: true,
            tagId: "episode-player",
            isInvisible: false
        )

        let preferred = WebMediaCandidateSelector.preferredCandidate(
            from: [staleBlob, refreshedDirect]
        )

        XCTAssertEqual(preferred?.src, refreshedDirect.src)
    }

    func testWebMediaCandidateSelectorAvoidsLikelyAdvertisementCandidates() {
        let advertisement = WebMediaInfo(
            name: "Pre-roll ad",
            src: "https://ads.doubleclick.net/preroll.mp4",
            pageSrc: "https://example.com/watch",
            pageTitle: "Sponsored preroll",
            mimeType: "video/mp4",
            duration: 15,
            detected: true,
            tagId: "ad-player",
            isInvisible: false
        )
        let content = WebMediaInfo(
            name: "Main episode",
            src: "https://cdn.example.com/main.mp4",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode",
            mimeType: "video/mp4",
            duration: 1800,
            detected: true,
            tagId: "main-player",
            isInvisible: false
        )

        let preferred = WebMediaCandidateSelector.preferredCandidate(
            from: [advertisement, content],
            preferringAudio: false
        )

        XCTAssertEqual(preferred?.tagId, "main-player")
    }

    func testWebMediaRequestContextBuilderIncludesCookieRefererAndUserAgent() {
        let cookie = HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session",
            .value: "abc123",
            .secure: "FALSE",
            .expires: Date().addingTimeInterval(60),
        ])!

        let context = WebMediaRequestContextBuilder.make(
            userAgent: "Manabi",
            referer: URL(string: "https://example.com/watch")!,
            cookies: [cookie]
        )

        XCTAssertEqual(context.headers["User-Agent"], "Manabi")
        XCTAssertEqual(context.headers["Referer"], "https://example.com/watch")
        XCTAssertEqual(context.headers["Cookie"], "session=abc123")
    }

    func testMediaStreamerResolvesDirectMedia() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "HEAD")
            XCTAssertNil(request.value(forHTTPHeaderField: "Range"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Manabi")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://example.com/watch/1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=abc123")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/mp4; charset=utf-8"]
            )!
            return (response, Data())
        }

        let streamer = WebMediaStreamer(urlSession: makeSession())
        let item = WebMediaInfo(
            name: "Audio",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Audio",
            mimeType: "",
            duration: 10,
            detected: true,
            tagId: "audio-1",
            isInvisible: false
        )

        let resolved = try await streamer.resolveMedia(
            item,
            requestContext: WebMediaRequestContext(
                userAgent: "Manabi",
                referer: URL(string: "https://example.com/watch/1"),
                cookieHeader: "session=abc123"
            )
        )
        XCTAssertEqual(resolved.url.absoluteString, item.src)
        XCTAssertEqual(resolved.mimeType, "audio/mp4")
        XCTAssertEqual(resolved.resolutionMethod, .direct)
        XCTAssertEqual(resolved.requestHeaders["User-Agent"], "Manabi")
        XCTAssertEqual(resolved.requestHeaders["Referer"], "https://example.com/watch/1")
        XCTAssertEqual(resolved.requestHeaders["Cookie"], "session=abc123")
    }

    func testMediaStreamerFallsBackToRangeGetWhenHeadProbeDoesNotReturnMimeType() async throws {
        let lock = NSLock()
        var methods: [String] = []

        URLProtocolStub.handler = { request in
            lock.lock()
            methods.append(request.httpMethod ?? "GET")
            lock.unlock()

            let response: HTTPURLResponse
            if request.httpMethod == "HEAD" {
                response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 405,
                    httpVersion: nil,
                    headerFields: nil
                )!
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-4095")
                response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 206,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "audio/mp4"]
                )!
            }
            return (response, Data())
        }

        let streamer = WebMediaStreamer(urlSession: makeSession())
        let item = WebMediaInfo(
            name: "Audio",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Audio",
            mimeType: "",
            duration: 10,
            detected: true,
            tagId: "audio-1",
            isInvisible: false
        )

        let resolved = try await streamer.resolveMedia(item)
        XCTAssertEqual(resolved.mimeType, "audio/mp4")
        XCTAssertEqual(methods, ["HEAD", "GET"])
    }

    func testMediaStreamerFallsBackWhenPrimaryURLIsBlob() async throws {
        var fallbackItem = WebMediaInfo(
            name: "Fallback",
            src: "https://r1.googlevideo.com/videoplayback?id=fixture",
            pageSrc: "https://www.youtube.com/watch?v=abcdefghijk",
            pageTitle: "Fallback",
            mimeType: "video/mp4",
            duration: 15,
            detected: true,
            tagId: "fallback-1",
            isInvisible: false
        )

        fallbackItem.durableResourceIdentity = "provider:youtube:abcdefghijk"

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data())
        }

        let streamer = WebMediaStreamer(
            urlSession: makeSession(),
            webLoaderFactory: MockLoaderFactory(item: fallbackItem)
        )

        var item = WebMediaInfo(
            name: "Blob",
            src: "blob:https://www.youtube.com/123",
            pageSrc: "https://www.youtube.com/watch?v=abcdefghijk",
            pageTitle: "Blob",
            mimeType: "",
            duration: 15,
            detected: true,
            tagId: "blob-1",
            isInvisible: false
        )

        item.durableResourceIdentity = "provider:youtube:abcdefghijk"
        let resolved = try await streamer.resolveMedia(item)
        XCTAssertEqual(resolved.mediaInfo.resourceLookupKey, item.resourceLookupKey)
        XCTAssertEqual(resolved.url.absoluteString, fallbackItem.src)
        XCTAssertEqual(resolved.resolutionMethod, .fallback)
    }

    func testMediaStreamerStopsFallbackLoaderAfterResolution() async throws {
        var fallbackItem = WebMediaInfo(
            name: "Fallback",
            src: "https://r1.googlevideo.com/videoplayback?id=fixture",
            pageSrc: "https://www.youtube.com/watch?v=abcdefghijk",
            pageTitle: "Fallback",
            mimeType: "video/mp4",
            duration: 15,
            detected: true,
            tagId: "fallback-1",
            isInvisible: false
        )

        fallbackItem.durableResourceIdentity = "provider:youtube:abcdefghijk"

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data())
        }

        let factory = MockLoaderFactory(item: fallbackItem)
        let streamer = WebMediaStreamer(
            urlSession: makeSession(),
            webLoaderFactory: factory
        )

        var item = WebMediaInfo(
            name: "Blob",
            src: "blob:https://www.youtube.com/123",
            pageSrc: "https://www.youtube.com/watch?v=abcdefghijk",
            pageTitle: "Blob",
            mimeType: "",
            duration: 15,
            detected: true,
            tagId: "blob-1",
            isInvisible: false
        )

        item.durableResourceIdentity = "provider:youtube:abcdefghijk"
        let resolved = try await streamer.resolveMedia(item)
        XCTAssertEqual(resolved.mediaInfo.resourceLookupKey, item.resourceLookupKey)
        XCTAssertEqual(factory.loader.stopCallCount, 1)
    }

    func testMediaStreamerRejectsFallbackForDifferentResource() async throws {
        let fallbackItem = WebMediaInfo(
            name: "Fallback",
            src: "https://media.example.com/video.mp4",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Fallback",
            mimeType: "video/mp4",
            duration: 15,
            detected: true,
            tagId: "fallback-1",
            isInvisible: false
        )

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data())
        }

        let streamer = WebMediaStreamer(
            urlSession: makeSession(),
            webLoaderFactory: MockLoaderFactory(item: fallbackItem)
        )

        let item = WebMediaInfo(
            name: "Blob",
            src: "blob:https://example.com/123",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Blob",
            mimeType: "",
            duration: 15,
            detected: true,
            tagId: "blob-1",
            isInvisible: false
        )

        do {
            _ = try await streamer.resolveMedia(item)
            XCTFail("A different media resource must not replace the requested resource")
        } catch let error as WebMediaStreamer.PlaybackError {
            XCTAssertEqual(error, .fallbackDidNotResolvePlayableMedia)
        }
    }


    func testMediaStreamerThrowsFallbackUnavailableForBlobWithoutResolver() async {
        let streamer = WebMediaStreamer(urlSession: makeSession())
        let item = WebMediaInfo(
            name: "Blob",
            src: "blob:https://example.com/123",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Blob",
            mimeType: "",
            duration: 15,
            detected: true,
            tagId: "blob-1",
            isInvisible: false
        )

        await XCTAssertThrowsErrorAsync(
            try await streamer.resolveMedia(item)
        ) { error in
            XCTAssertEqual(error as? WebMediaStreamer.PlaybackError, .fallbackUnavailable)
        }
    }

    func testMediaStreamerThrowsCouldNotDeterminePlayableMediaWhenDirectProbeFails() async {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let streamer = WebMediaStreamer(urlSession: makeSession())
        let item = WebMediaInfo(
            name: "Unknown",
            src: "https://cdn.example.com/stream",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Unknown",
            mimeType: "",
            duration: 10,
            detected: true,
            tagId: "unknown-1",
            isInvisible: false
        )

        await XCTAssertThrowsErrorAsync(
            try await streamer.resolveMedia(item)
        ) { error in
            XCTAssertEqual(error as? WebMediaStreamer.PlaybackError, .couldNotDeterminePlayableMedia)
        }
    }

    func testOfflineStoreDownloadsStoresThumbnailAndFindsMediaByPage() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )
        let resolvedMedia = ResolvedWebMedia(
            mediaInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=1")!,
            mimeType: "audio/mp4",
            requestHeaders: ["Cookie": "session=abc123"],
            resolutionMethod: .direct
        )

        let thumbnailData = Data("thumb".utf8)
        let storedMedia = try await fixture.store.download(
            resolvedMedia,
            storageScope: .transient,
            thumbnail: .inlineImageData(thumbnailData, fileExtension: "jpg")
        )

        XCTAssertEqual(storedMedia.storageScope, .transient)
        XCTAssertEqual(storedMedia.retentionPolicy, .manualTransient)
        XCTAssertEqual(storedMedia.storedMediaState, .storedTransient)
        XCTAssertEqual(try String(decoding: Data(contentsOf: storedMedia.localMediaURL), as: UTF8.self), "media-1")
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(storedMedia.localThumbnailURL)),
            thumbnailData
        )

        let byItem = try await fixture.store.storedMedia(for: item)
        XCTAssertEqual(byItem?.id, storedMedia.id)

        let byPage = try await fixture.store.storedMedia(
            forPageURL: URL(string: "https://example.com/watch?v=1")!
        )
        XCTAssertEqual(byPage.map(\.id), [storedMedia.id])
        let record = try await fixture.store.currentDownloadRecord(id: storedMedia.id)
        XCTAssertEqual(record?.storedMediaState, .storedTransient)
        XCTAssertEqual(record?.retentionPolicy, .manualTransient)
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
    }

    func testResolvedMediaSnapshotDecodesLegacyPlaylistInfoKeyAndReencodesMediaInfo() throws {
        let item = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )
        let snapshot = ResolvedWebMediaSnapshot(
            mediaInfo: item,
            resolvedMediaURL: URL(string: "https://cdn.example.com/audio.m4a?token=1")!,
            mimeType: "audio/mp4",
            requestHeaders: ["Cookie": "session=abc123"],
            resolutionMethod: .direct
        )

        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["playlistInfo"] = object.removeValue(forKey: "mediaInfo")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ResolvedWebMediaSnapshot.self, from: legacyData)
        XCTAssertEqual(decoded.mediaInfo.id, item.id)
        XCTAssertEqual(decoded.mediaInfo.src, item.src)
        XCTAssertEqual(decoded.resolvedMediaURL, snapshot.resolvedMediaURL)
        XCTAssertEqual(decoded.requestHeaders, snapshot.requestHeaders)

        let reencoded = try JSONEncoder().encode(decoded)
        let reencodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        XCTAssertNotNil(reencodedObject["mediaInfo"])
        XCTAssertNil(reencodedObject["playlistInfo"])
    }

    func testOfflineStoreDecodesLegacyPlaylistInfoMetadataAndReencodesMediaInfo() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = WebMediaInfo(
            name: "Legacy Episode",
            src: "https://cdn.example.com/legacy.m4a",
            pageSrc: "https://example.com/watch?v=legacy",
            pageTitle: "Legacy Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "legacy-episode",
            isInvisible: false
        )
        let stored = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: item,
                url: URL(string: "https://cdn.example.com/legacy.m4a?token=1")!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        let metadataURL = fixture.rootURL
            .appendingPathComponent("transient", isDirectory: true)
            .appendingPathComponent(stored.id, isDirectory: true)
            .appendingPathComponent("metadata.json", isDirectory: false)
        var metadataObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any]
        )
        metadataObject["playlistInfo"] = metadataObject.removeValue(forKey: "mediaInfo")
        var resolvedMediaObject = try XCTUnwrap(metadataObject["resolvedMedia"] as? [String: Any])
        resolvedMediaObject["playlistInfo"] = resolvedMediaObject.removeValue(forKey: "mediaInfo")
        metadataObject["resolvedMedia"] = resolvedMediaObject
        try JSONSerialization
            .data(withJSONObject: metadataObject)
            .write(to: metadataURL, options: .atomic)

        let loaded = try await fixture.store.allStoredMedia(scope: .transient)
        XCTAssertEqual(loaded.map(\.id), [stored.id])
        XCTAssertEqual(loaded.first?.mediaInfo.id, item.id)

        _ = try await fixture.store.touchStoredMedia(id: stored.id)
        let reencodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any]
        )
        XCTAssertNotNil(reencodedObject["mediaInfo"])
        XCTAssertNil(reencodedObject["playlistInfo"])
        let reencodedResolvedMedia = try XCTUnwrap(reencodedObject["resolvedMedia"] as? [String: Any])
        XCTAssertNotNil(reencodedResolvedMedia["mediaInfo"])
        XCTAssertNil(reencodedResolvedMedia["playlistInfo"])
    }

    func testOfflineStoreReusesExistingCandidateWithoutRedownloading() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )
        let initial = ResolvedWebMedia(
            mediaInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=1")!,
            mimeType: "audio/mp4",
            requestHeaders: [:],
            resolutionMethod: .direct
        )
        let refreshed = ResolvedWebMedia(
            mediaInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=2")!,
            mimeType: "audio/mp4",
            requestHeaders: [:],
            resolutionMethod: .fallback
        )

        let first = try await fixture.store.download(initial, storageScope: .transient)
        let second = try await fixture.store.download(refreshed, storageScope: .transient)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.resolvedMediaURL, first.resolvedMediaURL)
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
    }

    func testOfflineStoreSeparatesSameCandidateSourcesAndReusesSourceFragments() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }
        let pageSource = "https://example.com/watch?v=resource-identity"
        let firstItem = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/episode.m4a?source=A#first",
            pageSrc: pageSource,
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-resource",
            isInvisible: false
        )
        let secondItem = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/episode.m4a?source=B#first",
            pageSrc: pageSource,
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-resource",
            isInvisible: false
        )
        let matchingFragment = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/episode.m4a?source=A#second",
            pageSrc: pageSource,
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-resource",
            isInvisible: false
        )

        let first = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: firstItem,
                url: URL(string: firstItem.src)!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )
        let second = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: secondItem,
                url: URL(string: secondItem.src)!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )
        let matchingSource = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: matchingFragment,
                url: URL(string: matchingFragment.src)!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.id, matchingSource.id)
        XCTAssertEqual(fixture.downloader.downloadCallCount, 2)
        XCTAssertEqual(try String(decoding: Data(contentsOf: first.localMediaURL), as: UTF8.self), "media-1")
        XCTAssertEqual(try String(decoding: Data(contentsOf: second.localMediaURL), as: UTF8.self), "media-2")
        let storedFirst = try await fixture.store.storedMedia(for: firstItem)
        let storedSecond = try await fixture.store.storedMedia(for: secondItem)
        let firstRecord = try await fixture.store.downloadRecord(for: firstItem)
        let secondRecord = try await fixture.store.downloadRecord(for: secondItem)
        let fragmentRecord = try await fixture.store.downloadRecord(for: matchingFragment)
        let originalByIdentifier = try await fixture.store.storedMedia(id: first.id)
        XCTAssertEqual(storedFirst?.id, first.id)
        XCTAssertEqual(storedSecond?.id, second.id)
        XCTAssertEqual(firstRecord?.id, first.id)
        XCTAssertEqual(secondRecord?.id, second.id)
        XCTAssertEqual(fragmentRecord?.id, first.id)
        XCTAssertEqual(originalByIdentifier?.id, first.id)
    }

    func testOfflineStoreReusesMatchingLegacyDownloadedQueuedAndFailedIdentifiers() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }
        let pageSource = "https://example.com/watch?v=legacy-resource-identity"
        let downloadedItem = WebMediaInfo(
            name: "Downloaded",
            src: "https://cdn.example.com/downloaded.m4a?token=1#old",
            pageSrc: pageSource,
            pageTitle: "Legacy Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "legacy-downloaded",
            isInvisible: false
        )
        let queuedItem = WebMediaInfo(
            name: "Queued",
            src: "https://cdn.example.com/queued.m4a?token=1#old",
            pageSrc: pageSource,
            pageTitle: "Legacy Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "legacy-queued",
            isInvisible: false
        )
        let failedItem = WebMediaInfo(
            name: "Failed",
            src: "https://cdn.example.com/failed.m4a?token=1#old",
            pageSrc: pageSource,
            pageTitle: "Legacy Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "legacy-failed",
            isInvisible: false
        )
        let downloadedIdentifier = makeLegacyStoredMediaIdentifier(for: downloadedItem)
        let queuedIdentifier = makeLegacyStoredMediaIdentifier(for: queuedItem)
        let failedIdentifier = makeLegacyStoredMediaIdentifier(for: failedItem)
        let now = Date()

        try writeLegacyMetadata(
            for: downloadedItem,
            identifier: downloadedIdentifier,
            state: .downloaded,
            rootURL: fixture.rootURL,
            downloadedAt: now,
            mediaRelativePath: "media.mp4"
        )
        let downloadedDirectory = fixture.rootURL
            .appendingPathComponent("transient", isDirectory: true)
            .appendingPathComponent(downloadedIdentifier, isDirectory: true)
        try Data("legacy".utf8).write(to: downloadedDirectory.appendingPathComponent("media.mp4"))
        try writeLegacyMetadata(
            for: queuedItem,
            identifier: queuedIdentifier,
            state: .queued,
            rootURL: fixture.rootURL
        )
        try writeLegacyMetadata(
            for: failedItem,
            identifier: failedIdentifier,
            state: .failed,
            rootURL: fixture.rootURL
        )

        let matchingDownloaded = matchingFragmentItem(from: downloadedItem)
        let matchingQueued = matchingFragmentItem(from: queuedItem)
        let matchingFailed = matchingFragmentItem(from: failedItem)
        let downloaded = try await fixture.store.download(
            resolvedMedia(for: matchingDownloaded), storageScope: .transient, thumbnail: .none
        )
        let queued = try await fixture.store.enqueueDownload(
            resolvedMedia(for: matchingQueued), storageScope: .transient, thumbnail: .none
        )
        let completedQueued = try await fixture.store.waitForDownload(id: queued.id)
        let failed = try await fixture.store.enqueueDownload(
            resolvedMedia(for: matchingFailed), storageScope: .transient, thumbnail: .none
        )
        let completedFailed = try await fixture.store.waitForDownload(id: failed.id)

        XCTAssertEqual(downloaded.id, downloadedIdentifier)
        XCTAssertEqual(queued.id, queuedIdentifier)
        XCTAssertEqual(failed.id, failedIdentifier)
        XCTAssertEqual(completedQueued.id, queuedIdentifier)
        XCTAssertEqual(completedFailed.id, failedIdentifier)
        XCTAssertEqual(fixture.downloader.downloadCallCount, 2)
        for item in [downloadedItem, queuedItem, failedItem] {
            var replacement = item
            replacement.src = item.src.replacingOccurrences(of: "token=1", with: "token=2")
            let wrongResource = try await fixture.store.storedMedia(for: replacement)
            let wrongRecord = try await fixture.store.downloadRecord(for: replacement)
            XCTAssertNil(wrongResource)
            XCTAssertNil(wrongRecord)
        }
    }

    func testOfflineStorePromotesTransientMediaToPersistentWithoutRedownloading() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )
        let resolvedMedia = ResolvedWebMedia(
            mediaInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=1")!,
            mimeType: "audio/mp4",
            requestHeaders: [:],
            resolutionMethod: .direct
        )

        let transient = try await fixture.store.download(resolvedMedia, storageScope: .transient)
        let persistent = try await fixture.store.download(resolvedMedia, storageScope: .persistent)

        XCTAssertEqual(transient.id, persistent.id)
        XCTAssertEqual(persistent.storageScope, .persistent)
        XCTAssertEqual(persistent.retentionPolicy, .persistent)
        XCTAssertEqual(persistent.storedMediaState, .storedPersistent)
        XCTAssertTrue(persistent.localMediaURL.path.contains("/persistent/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transient.localMediaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistent.localMediaURL.path))
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
    }

    func testBestStoredMediaForPagePrefersPersistentMostRecentItem() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let pageURL = URL(string: "https://example.com/watch?v=shared")!
        let transient = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "Transient",
                    src: "https://cdn.example.com/transient.mp4",
                    pageSrc: pageURL.absoluteString,
                    pageTitle: "Shared Page",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "transient-item",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/transient.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )
        _ = transient

        let persistent = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "Persistent",
                    src: "https://cdn.example.com/persistent.mp4",
                    pageSrc: pageURL.absoluteString,
                    pageTitle: "Shared Page",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "persistent-item",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/persistent.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .persistent,
            thumbnail: .none
        )

        let preferred = try await fixture.store.bestStoredMedia(forPageURL: pageURL)
        XCTAssertEqual(preferred?.id, persistent.id)
        XCTAssertEqual(preferred?.storedMediaState, .storedPersistent)
    }

    func testOfflineStoreLazilyMaterializesThumbnailOnDemand() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=thumb-lazy",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-thumb-lazy",
            isInvisible: false
        )
        let thumbnailData = Data("lazy-thumb".utf8)
        let stored = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: item,
                url: URL(string: "https://cdn.example.com/audio.m4a?token=lazy")!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: WebMediaThumbnailRequest(
                loadingPolicy: .lazy,
                generateFromMedia: false,
                imageData: thumbnailData,
                fileExtension: "jpg"
            )
        )

        XCTAssertNil(stored.localThumbnailURL)

        let withThumbnail = try await fixture.store.ensureThumbnail(id: stored.id)
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(withThumbnail?.localThumbnailURL)),
            thumbnailData
        )
    }

    func testThumbnailPublicationPreservesConcurrentAccessAndPromotion() async throws {
        try await assertSuspendedThumbnailPublication(replacesMedia: false)
    }

    func testThumbnailPublicationRejectsDeletedAndReplacedMedia() async throws {
        try await assertSuspendedThumbnailPublication(replacesMedia: true)
    }

    private func assertSuspendedThumbnailPublication(replacesMedia: Bool) async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }
        let thumbnailData = Data("thumbnail".utf8)
        let item = WebMediaInfo(
            name: "Thumbnail", src: "https://example.com/thumbnail.m4a",
            pageSrc: "https://example.com/thumbnail", pageTitle: "Thumbnail",
            mimeType: "audio/mp4", duration: 10, detected: true, tagId: "thumbnail", isInvisible: false
        )
        let original = try await fixture.store.download(
            resolvedMedia(for: item), storageScope: .transient,
            thumbnail: .init(loadingPolicy: .lazy, generateFromMedia: false,
                             imageData: thumbnailData, fileExtension: "jpg")
        )
        let barrier = WebMediaPublicationBarrier()
        let thumbnailTask = Task {
            try await WebMediaOfflineStoreTesting.$beforeThumbnailPublication.withValue({ await barrier.suspend() }) {
                try await fixture.store.ensureThumbnail(id: original.id)
            }
        }
        await barrier.waitUntilArrived()
        do {
            if replacesMedia {
                try await fixture.store.deleteStoredMedia(id: original.id)
                _ = try await fixture.store.download(
                    resolvedMedia(for: item), storageScope: .transient, thumbnail: .none
                )
            } else {
                _ = try await fixture.store.updateRetentionPolicy(.persistent, for: original.id)
                _ = try await fixture.store.touchStoredMedia(id: original.id)
                try await fixture.store.purgeTransientMedia()
            }
        } catch {
            await barrier.release()
            _ = try? await thumbnailTask.value
            throw error
        }
        await barrier.release()
        let result = try await thumbnailTask.value
        let storedMedia = try await fixture.store.storedMedia(id: original.id)
        let current = try XCTUnwrap(storedMedia)
        if replacesMedia {
            XCTAssertNil(result)
            XCTAssertNil(current.localThumbnailURL)
            XCTAssertEqual(try Data(contentsOf: current.localMediaURL), Data("media-2".utf8))
        } else {
            XCTAssertEqual(result?.storageScope, .persistent)
            XCTAssertEqual(current.retentionPolicy, .persistent)
            XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(current.localThumbnailURL)), thumbnailData)
        }
    }

    func testOfflineStorePersistsAndUpdatesRetentionPolicy() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let stored = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "Episode",
                    src: "https://cdn.example.com/retain.mp4",
                    pageSrc: "https://example.com/watch?v=retain",
                    pageTitle: "Episode",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "retain-item",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/retain.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .untilPageChange,
            thumbnail: .none
        )

        XCTAssertEqual(stored.retentionPolicy, .untilPageChange)

        let updated = try await fixture.store.updateRetentionPolicy(.persistent, for: stored.id)
        XCTAssertEqual(updated.retentionPolicy, .persistent)
        XCTAssertEqual(updated.storageScope, .persistent)
        XCTAssertEqual(updated.storedMediaState, .storedPersistent)

        let persisted = try await fixture.store.storedMedia(id: stored.id)
        XCTAssertEqual(persisted?.retentionPolicy, .persistent)
        XCTAssertTrue(try XCTUnwrap(persisted?.localMediaURL.path).contains("/persistent/"))
    }

    func testOfflineStoreDeletesIndividuallyAndPurgesTransientMedia() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let persistentItem = WebMediaInfo(
            name: "Saved Episode",
            src: "https://cdn.example.com/saved.m4a",
            pageSrc: "https://example.com/watch?v=saved",
            pageTitle: "Saved Episode",
            mimeType: "audio/mp4",
            duration: 60,
            detected: true,
            tagId: "saved-1",
            isInvisible: false
        )
        let transientItem = WebMediaInfo(
            name: "Temp Episode",
            src: "https://cdn.example.com/temp.m4a",
            pageSrc: "https://example.com/watch?v=temp",
            pageTitle: "Temp Episode",
            mimeType: "audio/mp4",
            duration: 60,
            detected: true,
            tagId: "temp-1",
            isInvisible: false
        )

        let saved = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: persistentItem,
                url: URL(string: persistentItem.src)!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .persistent
        )
        _ = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: transientItem,
                url: URL(string: transientItem.src)!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient
        )

        try await fixture.store.deleteStoredMedia(id: saved.id)
        let deletedMedia = try await fixture.store.storedMedia(id: saved.id)
        XCTAssertNil(deletedMedia)

        try await fixture.store.purgeTransientMedia()
        let remainingMedia = try await fixture.store.allStoredMedia()
        XCTAssertEqual(remainingMedia.count, 0)
    }

    func testWebMediaLibraryResolvesAndDownloadsMediaIntoStore() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/mp4"]
            )!
            return (response, Data())
        }

        let library = WebMediaLibrary(
            mediaStreamer: WebMediaStreamer(urlSession: makeSession()),
            offlineStore: fixture.store
        )
        let item = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )

        let storedMedia = try await library.download(
            item,
            storageScope: .persistent,
            thumbnail: .none
        )

        XCTAssertEqual(storedMedia.storageScope, .persistent)
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
        let pageMedia = try await library.storedMedia(
            forPageURL: URL(string: "https://example.com/watch?v=1")!
        )
        XCTAssertEqual(pageMedia.count, 1)
    }

    func testWebMediaLibrariesShareAnInjectedOfflineStore() async throws {
        let fixture = try makeGatedOfflineStoreFixture()
        defer { fixture.cleanup() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/mp4"]
            )!
            return (response, Data())
        }

        let firstLibrary = WebMediaLibrary(
            mediaStreamer: WebMediaStreamer(urlSession: makeSession()),
            offlineStore: fixture.store
        )
        let secondLibrary = WebMediaLibrary(
            mediaStreamer: WebMediaStreamer(urlSession: makeSession()),
            offlineStore: fixture.store
        )
        let item = WebMediaInfo(
            name: "Shared episode",
            src: "https://cdn.example.com/shared.m4a",
            pageSrc: "https://example.com/watch?v=shared",
            pageTitle: "Shared episode",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "shared-episode",
            isInvisible: false
        )

        let firstRecord = try await firstLibrary.enqueueDownload(
            item,
            storageScope: .persistent,
            thumbnail: .none
        )
        await fixture.gate.waitForStarts(1)
        let secondRecord = try await secondLibrary.enqueueDownload(
            item,
            storageScope: .persistent,
            thumbnail: .none
        )
        let startedCount = await fixture.gate.currentStartCount()
        await fixture.gate.releaseNext(with: Data("shared".utf8))
        let storedMedia = try await secondLibrary.waitForDownload(id: secondRecord.id)

        XCTAssertEqual(firstRecord.id, secondRecord.id)
        XCTAssertEqual(storedMedia.id, firstRecord.id)
        XCTAssertEqual(startedCount, 1)
    }

    func testWebMediaLibraryExposesBestStoredMediaAndRetentionUpdates() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/mp4"]
            )!
            return (response, Data())
        }

        let library = WebMediaLibrary(
            mediaStreamer: WebMediaStreamer(urlSession: makeSession()),
            offlineStore: fixture.store
        )
        let pageURL = URL(string: "https://example.com/watch?v=library")!
        let item = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: pageURL.absoluteString,
            pageTitle: "Episode Page",
            mimeType: "",
            duration: 42,
            detected: true,
            tagId: "episode-library",
            isInvisible: false
        )

        let stored = try await library.download(
            item,
            storageScope: .transient,
            retentionPolicy: .untilSessionEnds,
            thumbnail: .none
        )
        let bestStored = try await library.bestStoredMedia(forPageURL: pageURL)
        XCTAssertEqual(bestStored?.id, stored.id)

        let updated = try await library.updateRetentionPolicy(.persistent, for: stored.id)
        XCTAssertEqual(updated.storageScope, .persistent)
        XCTAssertEqual(updated.retentionPolicy, .persistent)
    }

    func testOfflineStoreCanCancelAndRetryDownload() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let downloader = SequencedArtifactDownloader(
            steps: [
                .block(progress: .init(id: "placeholder", fractionCompleted: 0.5, bytesDownloaded: 5, totalBytesExpected: 10)),
                .success(data: Data("finished".utf8), relativePath: "media.mp4", mimeType: "audio/mp4")
            ]
        )
        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: downloader,
            urlSession: makeSession()
        )

        let record = try await store.enqueueDownload(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "Episode",
                    src: "https://cdn.example.com/cancel.mp4",
                    pageSrc: "https://example.com/watch?v=cancel",
                    pageTitle: "Episode",
                    mimeType: "audio/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "cancel-item",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/cancel.mp4")!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        let isDownloadingInitially = try await store.isDownloading(id: record.id)
        XCTAssertTrue(isDownloadingInitially)
        let cancelled = try await store.cancelDownload(id: record.id)
        XCTAssertEqual(cancelled?.state, .cancelled)
        XCTAssertEqual(cancelled?.storedMediaState, .cancelledTransient)
        let isDownloadingAfterCancel = try await store.isDownloading(id: record.id)
        XCTAssertFalse(isDownloadingAfterCancel)

        let retried = try await store.retryDownload(id: record.id)
        XCTAssertEqual(retried.state, .queued)
        let stored = try await store.waitForDownload(id: record.id)
        XCTAssertEqual(try String(decoding: Data(contentsOf: stored.localMediaURL), as: UTF8.self), "finished")
    }

    func testCancellingDownloadWaiterLeavesSharedDownloadRunning() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let gate = ArtifactDownloadGate()
        let downloader = GatedArtifactDownloader(gate: gate)
        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: downloader,
            urlSession: makeSession()
        )
        let item = WebMediaInfo(
            name: "Waiting episode",
            src: "https://cdn.example.com/waiting.mp4",
            pageSrc: "https://example.com/watch?v=waiting",
            pageTitle: "Waiting episode",
            mimeType: "audio/mp4",
            duration: 10,
            detected: true,
            tagId: "waiting-episode",
            isInvisible: false
        )
        let record = try await store.enqueueDownload(
            resolvedMedia(for: item),
            storageScope: .transient,
            thumbnail: .none
        )
        let waiterRegistered = expectation(description: "cancelled client's waiter registered")
        let waiter = Task { () -> Bool in
            await WebMediaOfflineStoreTesting.$downloadWaiterDidRegister.withValue({ waiterRegistered.fulfill() }) {
                do {
                    _ = try await store.waitForDownload(id: record.id)
                    return false
                } catch {
                    return error is CancellationError
                }
            }
        }
        let peer = Task { try await store.waitForDownload(id: record.id) }

        await gate.waitForStarts(1)
        await fulfillment(of: [waiterRegistered], timeout: 2)
        waiter.cancel()

        let waiterWasCancelled = await waiter.value
        let isDownloading = try await store.isDownloading(id: record.id)
        XCTAssertTrue(waiterWasCancelled)
        XCTAssertTrue(isDownloading)
        await gate.releaseNext(with: Data("completed".utf8))
        let peerStoredMedia = try await peer.value
        XCTAssertEqual(try String(decoding: Data(contentsOf: peerStoredMedia.localMediaURL), as: UTF8.self), "completed")
    }

    func testScopedDeletionCancelsTrackedDownloadBeforeRemovingItsDirectory() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let gate = ArtifactDownloadGate()
        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: GatedArtifactDownloader(gate: gate),
            urlSession: makeSession()
        )
        let item = WebMediaInfo(
            name: "Transient episode",
            src: "https://cdn.example.com/transient.mp4",
            pageSrc: "https://example.com/watch?v=transient",
            pageTitle: "Transient episode",
            mimeType: "audio/mp4",
            duration: 10,
            detected: true,
            tagId: "transient-episode",
            isInvisible: false
        )
        let record = try await store.enqueueDownload(
            resolvedMedia(for: item),
            storageScope: .transient,
            thumbnail: .none
        )

        await gate.waitForStarts(1)
        try await store.deleteAllStoredMedia(scope: .transient)

        let isDownloading = try await store.isDownloading(id: record.id)
        let currentRecord = try await store.currentDownloadRecord(id: record.id)
        XCTAssertFalse(isDownloading)
        XCTAssertNil(currentRecord)
        await gate.releaseNext(with: Data())
        await gate.waitForFinishedArtifacts(1)
    }

    func testLateDeletedAttemptCannotPublishOverReplacementDownload() async throws {
        let fixture = try makeGatedOfflineStoreFixture()
        defer { fixture.cleanup() }
        let item = WebMediaInfo(
            name: "Replacement episode",
            src: "https://cdn.example.com/replacement.mp4",
            pageSrc: "https://example.com/watch?v=replacement",
            pageTitle: "Replacement episode",
            mimeType: "audio/mp4",
            duration: 10,
            detected: true,
            tagId: "replacement-episode",
            isInvisible: false
        )
        let original = try await fixture.store.enqueueDownload(
            resolvedMedia(for: item),
            storageScope: .transient,
            thumbnail: .none
        )
        await fixture.gate.waitForStarts(1)
        try await fixture.store.deleteStoredMedia(id: original.id)
        let replacement = try await fixture.store.enqueueDownload(
            resolvedMedia(for: item), storageScope: .transient, thumbnail: .none
        )
        await fixture.gate.waitForStarts(2)

        await fixture.gate.release(at: 1, with: Data("replacement".utf8))
        let stored = try await fixture.store.waitForDownload(id: replacement.id)
        await fixture.gate.releaseNext(with: Data("old".utf8))
        await fixture.gate.waitForFinishedArtifacts(2)

        XCTAssertEqual(original.id, replacement.id)
        // The artifact has been written by the retired downloader before this
        // read; its metadata and final files must still belong to the replacement.
        XCTAssertEqual(try String(decoding: Data(contentsOf: stored.localMediaURL), as: UTF8.self), "replacement")
    }

    func testOfflineStoreEmitsDownloadEvents() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = WebMediaInfo(
            name: "Events",
            src: "https://cdn.example.com/events.mp4",
            pageSrc: "https://example.com/watch?v=events",
            pageTitle: "Events",
            mimeType: "video/mp4",
            duration: 10,
            detected: true,
            tagId: "events-item",
            isInvisible: false
        )
        let identifier = makeStoredMediaIdentifier(for: item)
        let stream = await fixture.store.downloadEvents(id: identifier)
        let collector = Task { () -> [WebMediaDownloadEventKind] in
            var kinds: [WebMediaDownloadEventKind] = []
            for await event in stream {
                kinds.append(event.kind)
                if event.kind == .completed {
                    break
                }
            }
            return kinds
        }

        _ = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: item,
                url: URL(string: "https://cdn.example.com/events.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        let kinds = await collector.value
        XCTAssertEqual(kinds.first, .queued)
        XCTAssertTrue(kinds.contains(.downloading) || kinds.contains(.progress))
        XCTAssertEqual(kinds.last, .completed)
    }

    func testOfflineStoreHandlesPageAndSessionRetentionCleanup() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let oldPage = URL(string: "https://example.com/watch?v=old")!
        let newPage = URL(string: "https://example.com/watch?v=new")!

        let pageBound = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "Old page",
                    src: "https://cdn.example.com/old.mp4",
                    pageSrc: oldPage.absoluteString,
                    pageTitle: "Old",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "old-page",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/old.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .untilPageChange,
            thumbnail: .none
        )
        let nextPageBound = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "New page",
                    src: "https://cdn.example.com/new.mp4",
                    pageSrc: newPage.absoluteString,
                    pageTitle: "New",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "new-page",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/new.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .untilPageChange,
            thumbnail: .none
        )
        let sessionBound = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "Session",
                    src: "https://cdn.example.com/session.mp4",
                    pageSrc: newPage.absoluteString,
                    pageTitle: "Session",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "session-page",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/session.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .untilSessionEnds,
            thumbnail: .none
        )
        let manual = try await fixture.store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "Manual",
                    src: "https://cdn.example.com/manual.mp4",
                    pageSrc: oldPage.absoluteString,
                    pageTitle: "Manual",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "manual-page",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/manual.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .manualTransient,
            thumbnail: .none
        )

        try await fixture.store.handlePageDidChange(from: oldPage, to: newPage)
        let oldPageAfterChange = try await fixture.store.storedMedia(id: pageBound.id)
        let newPageAfterChange = try await fixture.store.storedMedia(id: nextPageBound.id)
        let sessionAfterChange = try await fixture.store.storedMedia(id: sessionBound.id)
        let manualAfterChange = try await fixture.store.storedMedia(id: manual.id)
        XCTAssertNil(oldPageAfterChange)
        XCTAssertNotNil(newPageAfterChange)
        XCTAssertNotNil(sessionAfterChange)
        XCTAssertNotNil(manualAfterChange)

        try await fixture.store.handleSessionDidEnd()
        let newPageAfterSession = try await fixture.store.storedMedia(id: nextPageBound.id)
        let sessionAfterSession = try await fixture.store.storedMedia(id: sessionBound.id)
        let manualAfterSession = try await fixture.store.storedMedia(id: manual.id)
        XCTAssertNil(newPageAfterSession)
        XCTAssertNil(sessionAfterSession)
        XCTAssertNotNil(manualAfterSession)
    }

    func testOfflineStoreCanCancelAndRetryHLSDownload() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let hlsDownloader = SequencedHLSAssetDownloader(
            steps: [
                .block(progress: .init(id: "placeholder", fractionCompleted: 0.25, bytesDownloaded: 0, totalBytesExpected: nil)),
                .success(relativePath: "media.movpkg", mimeType: "application/vnd.apple.mpegurl")
            ]
        )
        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: WebMediaAssetDownloader(
                urlSession: makeSession(),
                hlsDownloaderFactory: { hlsDownloader }
            ),
            urlSession: makeSession()
        )

        let record = try await store.enqueueDownload(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "HLS retry",
                    src: "https://cdn.example.com/retry.m3u8",
                    pageSrc: "https://example.com/watch?v=hls-retry",
                    pageTitle: "HLS retry",
                    mimeType: "application/vnd.apple.mpegurl",
                    duration: 10,
                    detected: true,
                    tagId: "hls-retry",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/retry.m3u8")!,
                mimeType: "application/vnd.apple.mpegurl",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .persistent,
            thumbnail: .none
        )

        let isDownloadingInitially = try await store.isDownloading(id: record.id)
        XCTAssertTrue(isDownloadingInitially)
        let cancelled = try await store.cancelDownload(id: record.id)
        XCTAssertEqual(cancelled?.state, .cancelled)
        XCTAssertEqual(cancelled?.storedMediaState, .cancelledPersistent)

        let retried = try await store.retryDownload(id: record.id)
        XCTAssertEqual(retried.state, .queued)
        let stored = try await store.waitForDownload(id: record.id)
        XCTAssertTrue(stored.localMediaURL.path.hasSuffix("media.movpkg"))
    }

    func testOfflineStoreRestoresPendingDownloadsAfterRelaunch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let item = WebMediaInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=restore",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-restore",
            isInvisible: false
        )
        let resolvedMedia = ResolvedWebMedia(
            mediaInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=restore")!,
            mimeType: "audio/mp4",
            requestHeaders: ["Cookie": "session=abc123"],
            resolutionMethod: .direct
        )
        let identifier = makeLegacyStoredMediaIdentifier(for: item)
        let transientRoot = rootURL.appendingPathComponent("transient", isDirectory: true)
        let itemDirectory = transientRoot.appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)

        try writeMetadataFixture(
            PendingMetadataFixture(
                id: identifier,
                mediaInfo: item,
                storageScope: .transient,
                retentionPolicy: .manualTransient,
                resolvedMedia: .init(media: resolvedMedia),
                state: .downloading,
                createdAt: Date().addingTimeInterval(-10),
                updatedAt: Date().addingTimeInterval(-5),
                downloadedAt: nil,
                progress: .init(
                    id: identifier,
                    fractionCompleted: 0.4,
                    bytesDownloaded: 40,
                    totalBytesExpected: 100
                ),
                failureDescription: nil,
                mediaRelativePath: nil,
                thumbnailRelativePath: nil,
                byteCount: nil,
                thumbnailRequest: .none
            ),
            to: itemDirectory
        )

        let downloader = MockArtifactDownloader()
        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: transientRoot,
                excludeFromBackup: false
            ),
            downloader: downloader,
            urlSession: makeSession()
        )

        let restored = try await store.restorePendingDownloads()
        XCTAssertEqual(restored.map(\.id), [identifier])

        let storedMedia = try await store.waitForDownload(id: identifier)
        XCTAssertEqual(storedMedia.id, identifier)
        XCTAssertEqual(downloader.downloadCallCount, 1)

        let record = try await store.currentDownloadRecord(id: identifier)
        XCTAssertEqual(record?.state, .downloaded)
    }

    func testOfflineStoreRestoresPendingDownloadsByResumingPartialFileDownload() async throws {
        try await assertPendingPartialDownloadResumes(usesStaging: false)
    }

    func testOfflineStoreCancellingInterruptedStagedDownloadPreservesPartialForRetry() async throws {
        try await assertPendingPartialDownloadResumes(usesStaging: true, cancelBeforeRetry: true)
    }

    func testFailedDownloadPreservesStagedPartialForRetry() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = WebMediaOfflineStore(configuration: .init(
            persistentRootURL: rootURL.appendingPathComponent("persistent"),
            transientRootURL: rootURL.appendingPathComponent("transient"), excludeFromBackup: false
        ), downloader: PartialRetryArtifactDownloader())
        let item = WebMediaInfo(
            name: "Partial", src: "https://example.com/partial.m4a",
            pageSrc: "https://example.com/partial", pageTitle: "Partial",
            mimeType: "audio/mp4", duration: 10, detected: true, tagId: "partial", isInvisible: false
        )
        let record = try await store.enqueueDownload(
            resolvedMedia(for: item), storageScope: .transient, thumbnail: .none
        )
        do {
            _ = try await store.waitForDownload(id: record.id)
            XCTFail("The first attempt should fail after writing its partial bytes")
        } catch {}
        let failedRecord = try await store.currentDownloadRecord(id: record.id)
        XCTAssertEqual(failedRecord?.state, .failed)
        _ = try await store.retryDownload(id: record.id)
        let completed = try await store.waitForDownload(id: record.id)
        XCTAssertEqual(try Data(contentsOf: completed.localMediaURL), Data("hello world".utf8))
    }

    func testOfflineStoreResumesStagedPartialAfterProcessTermination() async throws {
        try await assertPendingPartialDownloadResumes(usesStaging: true)
    }

    private func assertPendingPartialDownloadResumes(
        usesStaging: Bool,
        cancelBeforeRetry: Bool = false
    ) async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let item = WebMediaInfo(
            name: "Resume",
            src: "https://cdn.example.com/resume.mp4",
            pageSrc: "https://example.com/watch?v=resume",
            pageTitle: "Resume Page",
            mimeType: "video/mp4",
            duration: 42,
            detected: true,
            tagId: "resume-item",
            isInvisible: false
        )
        let resolvedMedia = ResolvedWebMedia(
            mediaInfo: item,
            url: URL(string: "https://cdn.example.com/resume.mp4")!,
            mimeType: "video/mp4",
            requestHeaders: [:],
            resolutionMethod: .direct
        )
        let identifier = makeLegacyStoredMediaIdentifier(for: item)
        let transientRoot = rootURL.appendingPathComponent("transient", isDirectory: true)
        let itemDirectory = transientRoot.appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        let interruptedAttemptIdentifier = usesStaging ? UUID() : nil
        let partialDirectory = interruptedAttemptIdentifier.map {
            transientRoot.appendingPathComponent(".download-attempts", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true)
                .appendingPathComponent($0.uuidString, isDirectory: true)
        } ?? itemDirectory
        try FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: true)
        try Data("hello".utf8).write(
            to: partialDirectory.appendingPathComponent("media.partial"),
            options: .atomic
        )
        try writeResumeIdentity(for: resolvedMedia, in: partialDirectory)
        try writeMetadataFixture(
            PendingMetadataFixture(
                id: identifier,
                mediaInfo: item,
                storageScope: .transient,
                retentionPolicy: .manualTransient,
                resolvedMedia: .init(media: resolvedMedia),
                state: .downloading,
                createdAt: Date().addingTimeInterval(-10),
                updatedAt: Date().addingTimeInterval(-5),
                downloadedAt: nil,
                progress: .init(
                    id: identifier,
                    fractionCompleted: 0.5,
                    bytesDownloaded: 5,
                    totalBytesExpected: 10
                ),
                failureDescription: nil,
                mediaRelativePath: nil,
                thumbnailRelativePath: nil,
                byteCount: nil,
                thumbnailRequest: .none,
                downloadAttemptIdentifier: interruptedAttemptIdentifier
            ),
            to: itemDirectory
        )

        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=5-")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Range"), "\"fixture-v1\"")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4", "ETag": "\"fixture-v1\"", "Content-Range": "bytes 5-9/10"]
            )!
            return (response, Data("world".utf8))
        }

        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: transientRoot,
                excludeFromBackup: false
            ),
            downloader: WebMediaAssetDownloader(urlSession: makeSession()),
            urlSession: makeSession()
        )

        if cancelBeforeRetry {
            let cancelled = try await store.cancelDownload(id: identifier)
            XCTAssertEqual(cancelled?.state, .cancelled)
            XCTAssertEqual(cancelled?.storedMediaState, .cancelledTransient)
            _ = try await store.retryDownload(id: identifier)
        } else {
            _ = try await store.restorePendingDownloads()
        }
        let storedMedia = try await store.waitForDownload(id: identifier)
        XCTAssertEqual(
            try String(decoding: Data(contentsOf: storedMedia.localMediaURL), as: UTF8.self),
            "helloworld"
        )
    }

    func testOfflineStoreDeletionRemovesOnlyMatchingDownloadAttemptDirectories() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let stored = try await fixture.store.download(
            resolvedMedia(for: WebMediaInfo(
                name: "Delete attempts",
                src: "https://cdn.example.com/delete-attempts.mp4",
                pageSrc: "https://example.com/delete-attempts",
                pageTitle: "Delete attempts",
                mimeType: "video/mp4",
                duration: 42,
                detected: true,
                tagId: "delete-attempts",
                isInvisible: false
            )),
            storageScope: .transient,
            thumbnail: .none
        )
        let otherIdentifier = "other-download-attempt"
        let transientAttempts = fixture.rootURL
            .appendingPathComponent("transient", isDirectory: true)
            .appendingPathComponent(".download-attempts", isDirectory: true)
        let selectedTransientAttempt = transientAttempts.appendingPathComponent(stored.id, isDirectory: true)
        let selectedPersistentAttempt = fixture.rootURL
            .appendingPathComponent("persistent", isDirectory: true)
            .appendingPathComponent(".download-attempts", isDirectory: true)
            .appendingPathComponent(stored.id, isDirectory: true)
        let otherAttempt = transientAttempts.appendingPathComponent(otherIdentifier, isDirectory: true)
        for directory in [selectedTransientAttempt, selectedPersistentAttempt, otherAttempt] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("partial".utf8).write(to: directory.appendingPathComponent("media.partial"))
        }

        try await fixture.store.deleteStoredMedia(id: stored.id)

        let deleted = try await fixture.store.storedMedia(id: stored.id)
        XCTAssertNil(deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.localMediaURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedTransientAttempt.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedPersistentAttempt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherAttempt.path))
    }

    func testOfflineStoreNormalizesScopeFromPhysicalRootAfterUnrecordedRelocation() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let transientItem = WebMediaInfo(
            name: "Promoted",
            src: "https://cdn.example.com/promoted.mp4",
            pageSrc: "https://example.com/promoted",
            pageTitle: "Promoted",
            mimeType: "video/mp4",
            duration: 42,
            detected: true,
            tagId: "promoted",
            isInvisible: false
        )
        let persistentItem = WebMediaInfo(
            name: "Demoted",
            src: "https://cdn.example.com/demoted.mp4",
            pageSrc: "https://example.com/demoted",
            pageTitle: "Demoted",
            mimeType: "video/mp4",
            duration: 42,
            detected: true,
            tagId: "demoted",
            isInvisible: false
        )
        let promoted = try await fixture.store.download(
            resolvedMedia(for: transientItem), storageScope: .transient, thumbnail: .none
        )
        let demoted = try await fixture.store.download(
            resolvedMedia(for: persistentItem), storageScope: .persistent, thumbnail: .none
        )
        let transientRoot = fixture.rootURL.appendingPathComponent("transient", isDirectory: true)
        let persistentRoot = fixture.rootURL.appendingPathComponent("persistent", isDirectory: true)
        try FileManager.default.moveItem(
            at: transientRoot.appendingPathComponent(promoted.id, isDirectory: true),
            to: persistentRoot.appendingPathComponent(promoted.id, isDirectory: true)
        )
        try FileManager.default.moveItem(
            at: persistentRoot.appendingPathComponent(demoted.id, isDirectory: true),
            to: transientRoot.appendingPathComponent(demoted.id, isDirectory: true)
        )

        let normalizedPromoted = try await fixture.store.updateStorageScope(.persistent, for: promoted.id)
        let normalizedDemoted = try await fixture.store.updateStorageScope(.transient, for: demoted.id)
        let persistentMedia = try await fixture.store.allStoredMedia(scope: .persistent)
        let transientMedia = try await fixture.store.allStoredMedia(scope: .transient)
        let normalizedPromotedMedia = try await fixture.store.storedMedia(id: promoted.id)
        let normalizedDemotedMedia = try await fixture.store.storedMedia(id: demoted.id)
        XCTAssertEqual(normalizedPromoted.storageScope, .persistent)
        XCTAssertEqual(normalizedDemoted.storageScope, .transient)
        XCTAssertEqual(persistentMedia.map(\.id), [promoted.id])
        XCTAssertEqual(transientMedia.map(\.id), [demoted.id])
        XCTAssertEqual(normalizedPromotedMedia?.storageScope, .persistent)
        XCTAssertEqual(normalizedDemotedMedia?.storageScope, .transient)
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(normalizedPromotedMedia?.localMediaURL)),
            Data("media-1".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(normalizedDemotedMedia?.localMediaURL)),
            Data("media-2".utf8)
        )
    }

    func testTransientStoragePolicyExemptsCurrentPageBeforeEvictingOldestTransientMedia() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let downloader = MockArtifactDownloader()
        var store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false,
                transientStoragePolicy: .init(maxItemCount: nil, maxTotalByteCount: nil, maxAge: nil)
            ),
            downloader: downloader,
            urlSession: makeSession()
        )

        let first = try await store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "First",
                    src: "https://cdn.example.com/first.mp4",
                    pageSrc: "https://example.com/watch?v=1",
                    pageTitle: "First",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "first",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/first.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        let second = try await store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "Second",
                    src: "https://cdn.example.com/second.mp4",
                    pageSrc: "https://example.com/watch?v=2",
                    pageTitle: "Second",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "second",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/second.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        // Seed without quota enforcement, then reopen the same inventory with
        // a quota. Download completion itself now applies the configured policy.
        store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false,
                transientStoragePolicy: .init(maxItemCount: 1, maxTotalByteCount: nil, maxAge: nil)
            ),
            downloader: downloader,
            urlSession: makeSession()
        )

        let allTransientBeforeTrim = try await store.allStoredMedia(scope: .transient)
        XCTAssertEqual(Set(allTransientBeforeTrim.map(\.id)), Set([first.id, second.id]))

        try await store.enforceTransientStoragePolicy(exceptPageURLs: [URL(string: "https://example.com/watch?v=1")!])
        let allTransientWithCurrentPageExempt = try await store.allStoredMedia(scope: .transient)
        XCTAssertEqual(allTransientWithCurrentPageExempt.map(\.id), [first.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.localMediaURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.localMediaURL.path))
    }

    func testAssetDownloaderUsesHLSDownloaderPath() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let hlsDownloader = MockHLSAssetDownloader()
        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: WebMediaAssetDownloader(
                urlSession: makeSession(),
                hlsDownloaderFactory: { hlsDownloader }
            ),
            urlSession: makeSession()
        )

        let storedMedia = try await store.download(
            ResolvedWebMedia(
                mediaInfo: WebMediaInfo(
                    name: "HLS Episode",
                    src: "https://cdn.example.com/master.m3u8",
                    pageSrc: "https://example.com/watch?v=hls",
                    pageTitle: "HLS Episode",
                    mimeType: "application/vnd.apple.mpegurl",
                    duration: 10,
                    detected: true,
                    tagId: "hls-episode",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/master.m3u8")!,
                mimeType: "application/vnd.apple.mpegurl",
                requestHeaders: ["Cookie": "session=abc123"],
                resolutionMethod: .direct
            ),
            storageScope: .persistent,
            thumbnail: .none
        )

        XCTAssertTrue(hlsDownloader.didDownload)
        XCTAssertEqual(hlsDownloader.lastIdentifier, storedMedia.id)
        XCTAssertTrue(storedMedia.localMediaURL.path.hasSuffix("media.movpkg"))
    }

    func testAssetDownloaderRejectsInvalidPartialContentRangesWithoutMutatingPartial() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let cases: [(name: String, contentRange: String?)] = [
            ("absent", nil),
            ("malformed", "not-a-range"),
            ("wrong start", "bytes 0-4/10"),
            ("short range", "bytes 5-7/10")
        ]
        let downloader = WebMediaAssetDownloader(urlSession: makeSession())
        let media = resolvedMedia(for: WebMediaInfo(
            name: "Range validation",
            src: "https://cdn.example.com/range-validation.mp4",
            pageSrc: "https://example.com/range-validation",
            pageTitle: "Range validation",
            mimeType: "video/mp4",
            duration: 10,
            detected: true,
            tagId: "range-validation",
            isInvisible: false
        ))

        for invalidRange in cases {
            let directory = rootURL.appendingPathComponent(invalidRange.name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let partialURL = directory.appendingPathComponent("media.partial", isDirectory: false)
            try Data("hello".utf8).write(to: partialURL)
            try writeResumeIdentity(for: media, in: directory)
            let requestLock = NSLock()
            var requests: [URLRequest] = []
            URLProtocolStub.handler = { request in
                requestLock.withLock { requests.append(request) }
                var headers = ["Content-Type": "video/mp4", "ETag": "\"fixture-v1\""]
                if let contentRange = invalidRange.contentRange {
                    headers["Content-Range"] = contentRange
                }
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 206,
                    httpVersion: nil,
                    headerFields: headers
                )!
                return (response, Data("world".utf8))
            }

            do {
                _ = try await downloader.download(
                    media: media,
                    into: directory,
                    identifier: invalidRange.name,
                    onProgress: { _ in }
                )
                XCTFail("Expected invalid range \(invalidRange.name) to be rejected")
            } catch let error as WebMediaOfflineStoreError {
                XCTAssertEqual(error, .invalidResponse)
            } catch {
                XCTFail("Expected invalidResponse for \(invalidRange.name), received \(error)")
            }

            let observedRequests = requestLock.withLock { requests }
            XCTAssertEqual(observedRequests.count, 2)
            XCTAssertEqual(observedRequests.first?.value(forHTTPHeaderField: "Range"), "bytes=5-")
            XCTAssertEqual(observedRequests.first?.value(forHTTPHeaderField: "If-Range"), "\"fixture-v1\"")
            XCTAssertNil(observedRequests.last?.value(forHTTPHeaderField: "Range"))
            XCTAssertNil(observedRequests.last?.value(forHTTPHeaderField: "If-Range"))
            XCTAssertEqual(try Data(contentsOf: partialURL), Data("hello".utf8))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("media.mp4", isDirectory: false).path
            ))
        }
    }

    func testAssetDownloaderRejectsTruncatedPartialContentRangeWithoutPublishingArtifact() async throws {
        try await assertPartialContentBodyMismatch(Data("wor".utf8))
    }

    func testAssetDownloaderRejectsOversizedPartialContentRangeWithoutPublishingArtifact() async throws {
        try await assertPartialContentBodyMismatch(Data("world!".utf8))
    }

    private func assertPartialContentBodyMismatch(_ payload: Data) async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let partialURL = rootURL.appendingPathComponent("media.partial", isDirectory: false)
        try Data("hello".utf8).write(to: partialURL)
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=5-")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Range"), "\"fixture-v1\"")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4", "ETag": "\"fixture-v1\"", "Content-Range": "bytes 5-9/10"]
            )!
            return (response, payload)
        }

        let downloader = WebMediaAssetDownloader(urlSession: makeSession())
        let media = resolvedMedia(for: WebMediaInfo(
            name: "Truncated range",
            src: "https://cdn.example.com/truncated-range.mp4",
            pageSrc: "https://example.com/truncated-range",
            pageTitle: "Truncated range",
            mimeType: "video/mp4",
            duration: 10,
            detected: true,
            tagId: "truncated-range",
            isInvisible: false
        ))

        try writeResumeIdentity(for: media, in: rootURL)
        do {
            _ = try await downloader.download(media: media, into: rootURL, identifier: "truncated") { _ in }
            XCTFail("Expected mismatched range body length to be rejected")
        } catch let error as WebMediaOfflineStoreError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Expected invalidResponse for mismatched range body length, received \(error)")
        }

        XCTAssertEqual(try Data(contentsOf: partialURL), Data("hello".utf8))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("media.mp4", isDirectory: false).path
        ))
    }

    func testAssetDownloaderReplacesPartialWhenServerIgnoresRange() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let partialURL = rootURL.appendingPathComponent("media.partial", isDirectory: false)
        try Data("hello".utf8).write(to: partialURL)
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=5-")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Range"), "\"fixture-v1\"")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data("replacement".utf8))
        }

        let downloader = WebMediaAssetDownloader(urlSession: makeSession())
        let media = resolvedMedia(for: WebMediaInfo(
            name: "Range ignored",
            src: "https://cdn.example.com/range-ignored.mp4",
            pageSrc: "https://example.com/range-ignored",
            pageTitle: "Range ignored",
            mimeType: "video/mp4",
            duration: 10,
            detected: true,
            tagId: "range-ignored",
            isInvisible: false
        ))

        try writeResumeIdentity(for: media, in: rootURL)
        let artifact = try await downloader.download(
            media: media,
            into: rootURL,
            identifier: "range-ignored",
            onProgress: { _ in }
        )
        let finalURL = rootURL.appendingPathComponent(artifact.relativeMediaPath, isDirectory: false)
        XCTAssertEqual(artifact.byteCount, Int64(Data("replacement".utf8).count))
        XCTAssertEqual(try Data(contentsOf: finalURL), Data("replacement".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
    }

    func testAssetDownloaderAcceptsPartialContentRangeWithUnknownTotalLength() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let partialURL = rootURL.appendingPathComponent("media.partial", isDirectory: false)
        try Data("hello".utf8).write(to: partialURL)
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=5-")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Range"), "\"fixture-v1\"")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4", "ETag": "\"fixture-v1\"", "Content-Range": "bytes 5-9/*"]
            )!
            return (response, Data("world".utf8))
        }

        let media = resolvedMedia(for: WebMediaInfo(
            name: "Unknown total", src: "https://cdn.example.com/unknown-total.mp4",
            pageSrc: "https://example.com/unknown-total", pageTitle: "Unknown total",
            mimeType: "video/mp4", duration: 10, detected: true, tagId: "unknown-total", isInvisible: false
        ))
        let downloader = WebMediaAssetDownloader(urlSession: makeSession())
        try writeResumeIdentity(for: media, in: rootURL)
        let artifact = try await downloader.download(
            media: media, into: rootURL, identifier: "unknown-total", onProgress: { _ in }
        )
        XCTAssertEqual(artifact.byteCount, 10)
        XCTAssertEqual(
            try Data(contentsOf: rootURL.appendingPathComponent(artifact.relativeMediaPath)),
            Data("helloworld".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
    }

    private func writeResumeIdentity(for media: ResolvedWebMedia, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let headers = try encoder.encode(media.requestHeaders)
        let requestKey = SHA256.hash(data: Data(media.url.absoluteString.utf8) + headers)
            .map { String(format: "%02x", $0) }.joined()
        let data = try JSONSerialization.data(withJSONObject: [
            "requestKey": requestKey,
            "responseURL": media.url.absoluteString,
            "etag": "\"fixture-v1\"",
            "totalLength": 10,
        ])
        try data.write(to: directory.appendingPathComponent("media.partial.identity.json"), options: .atomic)
    }

    func testAssetDownloaderRejectsChangedETagWithoutAppending() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let media = resolvedMedia(for: WebMediaInfo(
            name: "Changed representation", src: "https://cdn.example.com/changed.mp4",
            pageSrc: "https://example.com/changed", pageTitle: "Changed",
            mimeType: "video/mp4", duration: 10, detected: true, tagId: "changed", isInvisible: false
        ))
        let partial = directory.appendingPathComponent("media.partial")
        try Data("hello".utf8).write(to: partial)
        try writeResumeIdentity(for: media, in: directory)
        let requestLock = NSLock()
        var requests: [URLRequest] = []
        URLProtocolStub.handler = { request in
            requestLock.withLock { requests.append(request) }
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 206, httpVersion: nil,
                                   headerFields: ["ETag": "\"fixture-v2\"", "Content-Range": "bytes 5-9/10"])!,
                    Data("other".utf8))
        }
        do {
            _ = try await WebMediaAssetDownloader(urlSession: makeSession()).download(
                media: media, into: directory, identifier: "changed", onProgress: { _ in }
            )
            XCTFail("A changed representation must not be appended")
        } catch let error as WebMediaOfflineStoreError {
            XCTAssertEqual(error, .invalidResponse)
        }
        let observedRequests = requestLock.withLock { requests }
        XCTAssertEqual(observedRequests.count, 2)
        XCTAssertEqual(observedRequests.first?.value(forHTTPHeaderField: "Range"), "bytes=5-")
        XCTAssertEqual(observedRequests.first?.value(forHTTPHeaderField: "If-Range"), "\"fixture-v1\"")
        XCTAssertNil(observedRequests.last?.value(forHTTPHeaderField: "Range"))
        XCTAssertNil(observedRequests.last?.value(forHTTPHeaderField: "If-Range"))
        XCTAssertEqual(try Data(contentsOf: partial), Data("hello".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("media.mp4").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("media.partial.identity.json").path))
    }

    func testUnreadableMetadataPreservesPersistentPayload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistent = root.appendingPathComponent("persistent")
        let item = persistent.appendingPathComponent("unreadable-item")
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        let original = Data("persisted media".utf8)
        try original.write(to: item.appendingPathComponent("media.mp4"))
        try Data("invalid metadata".utf8).write(to: item.appendingPathComponent("metadata.json"))
        let store = WebMediaOfflineStore(configuration: .init(
            persistentRootURL: persistent, transientRootURL: root.appendingPathComponent("transient"),
            excludeFromBackup: false
        ))
        let records = try await store.allDownloadRecords()
        XCTAssertTrue(records.isEmpty)
        let issues = await store.recoveryIssues()
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.directoryURL.standardizedFileURL.path, item.standardizedFileURL.path)
        XCTAssertFalse(try XCTUnwrap(issues.first).description.isEmpty)
        XCTAssertEqual(try Data(contentsOf: item.appendingPathComponent("media.mp4")), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.appendingPathComponent("metadata.json").path))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeOfflineStoreFixture() throws -> OfflineStoreFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloader = MockArtifactDownloader()
        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: downloader,
            urlSession: makeSession()
        )
        return OfflineStoreFixture(rootURL: rootURL, store: store, downloader: downloader)
    }

    private func makeGatedOfflineStoreFixture() throws -> GatedOfflineStoreFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let gate = ArtifactDownloadGate()
        let store = WebMediaOfflineStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: GatedArtifactDownloader(gate: gate),
            urlSession: makeSession()
        )
        return GatedOfflineStoreFixture(rootURL: rootURL, store: store, gate: gate)
    }
}

private final class MockLoaderFactory: WebMediaLoaderFactory {
    let loader: MockWebLoader

    init(item: WebMediaInfo) {
        self.loader = MockWebLoader(item: item)
    }

    func makeWebLoader() -> any WebMediaLoader {
        loader
    }
}

private final class MockWebLoader: WebMediaLoader {
    private let item: WebMediaInfo
    private(set) var stopCallCount = 0

    init(item: WebMediaInfo) {
        self.item = item
    }

    func load(url: URL) async -> WebMediaInfo? {
        item
    }

    func stop() {
        stopCallCount += 1
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("URLProtocolStub.handler not set")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct OfflineStoreFixture {
    let rootURL: URL
    let store: WebMediaOfflineStore
    let downloader: MockArtifactDownloader

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct GatedOfflineStoreFixture {
    let rootURL: URL
    let store: WebMediaOfflineStore
    let gate: ArtifactDownloadGate

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor ArtifactDownloadGate {
    private var startedCount = 0
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var payloadWaiters: [CheckedContinuation<Data, Never>] = []
    private var finishedArtifactCount = 0
    private var finishWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func nextPayload() async -> Data {
        startedCount += 1
        resumeStartedWaiters()
        return await withCheckedContinuation { continuation in
            payloadWaiters.append(continuation)
        }
    }

    func waitForStarts(_ count: Int) async {
        guard startedCount < count else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func currentStartCount() -> Int {
        startedCount
    }

    func releaseNext(with data: Data) {
        release(at: 0, with: data)
    }

    func release(at index: Int, with data: Data) {
        guard payloadWaiters.indices.contains(index) else {
            return
        }
        payloadWaiters.remove(at: index).resume(returning: data)
    }

    func artifactDidFinish() {
        finishedArtifactCount += 1
        let ready = finishWaiters.filter { $0.0 <= finishedArtifactCount }
        finishWaiters.removeAll { $0.0 <= finishedArtifactCount }
        for (_, continuation) in ready { continuation.resume() }
    }

    func waitForFinishedArtifacts(_ count: Int) async {
        guard finishedArtifactCount < count else { return }
        await withCheckedContinuation { finishWaiters.append((count, $0)) }
    }

    private func resumeStartedWaiters() {
        let readyWaiters = startWaiters.filter { $0.0 <= startedCount }
        startWaiters.removeAll { $0.0 <= startedCount }
        for (_, continuation) in readyWaiters {
            continuation.resume()
        }
    }
}

private final class GatedArtifactDownloader: WebMediaArtifactDownloading, @unchecked Sendable {
    private let gate: ArtifactDownloadGate

    init(gate: ArtifactDownloadGate) {
        self.gate = gate
    }

    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        let payload = await gate.nextPayload()
        let destinationURL = directory.appendingPathComponent("media.mp4", isDirectory: false)
        // Deliberately ignore cancellation and recreate the obsolete attempt's
        // directory so its late write exercises physical artifact isolation.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try payload.write(to: destinationURL, options: .atomic)
        onProgress(
            WebMediaDownloadProgress(
                id: identifier,
                fractionCompleted: 1,
                bytesDownloaded: Int64(payload.count),
                totalBytesExpected: Int64(payload.count)
            )
        )
        await gate.artifactDidFinish()
        return DownloadedWebMediaArtifact(
            relativeMediaPath: "media.mp4",
            mimeType: media.mimeType,
            byteCount: Int64(payload.count)
        )
    }
}

private final class MockArtifactDownloader: WebMediaArtifactDownloading, @unchecked Sendable {
    private(set) var downloadCallCount = 0

    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        downloadCallCount += 1

        let payload = Data("media-\(downloadCallCount)".utf8)
        let relativePath = "media.mp4"
        let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
        try payload.write(to: destinationURL, options: .atomic)

        onProgress(
            WebMediaDownloadProgress(
                id: identifier,
                fractionCompleted: 1,
                bytesDownloaded: Int64(payload.count),
                totalBytesExpected: Int64(payload.count)
            )
        )

        return DownloadedWebMediaArtifact(
            relativeMediaPath: relativePath,
            mimeType: media.mimeType,
            byteCount: Int64(payload.count)
        )
    }
}

private final class SequencedArtifactDownloader: WebMediaArtifactDownloading, @unchecked Sendable {
    enum Step {
        case block(progress: WebMediaDownloadProgress)
        case success(data: Data, relativePath: String, mimeType: String?)
    }

    private let lock = NSLock()
    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        let step: Step = lock.withLock {
            precondition(steps.isEmpty == false)
            return steps.removeFirst()
        }

        switch step {
        case .block(let progress):
            onProgress(
                WebMediaDownloadProgress(
                    id: identifier,
                    fractionCompleted: progress.fractionCompleted,
                    bytesDownloaded: progress.bytesDownloaded,
                    totalBytesExpected: progress.totalBytesExpected
                )
            )
            try await Task.sleep(nanoseconds: 5_000_000_000)
            try Task.checkCancellation()
            throw CancellationError()
        case .success(let data, let relativePath, let mimeType):
            let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
            try data.write(to: destinationURL, options: .atomic)
            onProgress(
                WebMediaDownloadProgress(
                    id: identifier,
                    fractionCompleted: 1,
                    bytesDownloaded: Int64(data.count),
                    totalBytesExpected: Int64(data.count)
                )
            )
            return DownloadedWebMediaArtifact(
                relativeMediaPath: relativePath,
                mimeType: mimeType ?? media.mimeType,
                byteCount: Int64(data.count)
            )
        }
    }
}

private final class SequencedHLSAssetDownloader: WebMediaHLSAssetDownloading, @unchecked Sendable {
    enum Step {
        case block(progress: WebMediaDownloadProgress)
        case success(relativePath: String, mimeType: String?)
    }

    private let lock = NSLock()
    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        let step: Step = lock.withLock {
            precondition(steps.isEmpty == false)
            return steps.removeFirst()
        }

        switch step {
        case .block(let progress):
            onProgress(
                WebMediaDownloadProgress(
                    id: identifier,
                    fractionCompleted: progress.fractionCompleted,
                    bytesDownloaded: progress.bytesDownloaded,
                    totalBytesExpected: progress.totalBytesExpected
                )
            )
            try await Task.sleep(nanoseconds: 5_000_000_000)
            try Task.checkCancellation()
            throw CancellationError()
        case .success(let relativePath, let mimeType):
            let packageDirectory = directory.appendingPathComponent(relativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            try Data("segment".utf8).write(to: packageDirectory.appendingPathComponent("segment.ts"))
            onProgress(
                WebMediaDownloadProgress(
                    id: identifier,
                    fractionCompleted: 1,
                    bytesDownloaded: 7,
                    totalBytesExpected: 7
                )
            )
            return DownloadedWebMediaArtifact(
                relativeMediaPath: relativePath,
                mimeType: mimeType ?? media.mimeType,
                byteCount: 7
            )
        }
    }
}

private final class MockHLSAssetDownloader: WebMediaHLSAssetDownloading, @unchecked Sendable {
    private(set) var didDownload = false
    private(set) var lastIdentifier: String?

    func download(
        media: ResolvedWebMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        didDownload = true
        lastIdentifier = identifier
        let packageDirectory = directory.appendingPathComponent("media.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        let segmentURL = packageDirectory.appendingPathComponent("segment.ts", isDirectory: false)
        try Data("segment".utf8).write(to: segmentURL)
        onProgress(
            WebMediaDownloadProgress(
                id: identifier,
                fractionCompleted: 1,
                bytesDownloaded: 7,
                totalBytesExpected: 7
            )
        )
        return DownloadedWebMediaArtifact(
            relativeMediaPath: "media.movpkg",
            mimeType: media.mimeType,
            byteCount: 7
        )
    }
}

private actor WebMediaPublicationBarrier {
    private var hasArrived = false
    private var isReleased = false
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        hasArrived = true
        for continuation in arrivals { continuation.resume() }
        arrivals.removeAll()
        guard !isReleased else { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilArrived() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { arrivals.append($0) }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor PartialRetryArtifactDownloader: WebMediaArtifactDownloading {
    private var hasFailed = false

    func download(
        media: ResolvedWebMedia, into directory: URL, identifier: String,
        onProgress: @escaping @Sendable (WebMediaDownloadProgress) -> Void
    ) async throws -> DownloadedWebMediaArtifact {
        let partialURL = directory.appendingPathComponent("media.partial")
        if !hasFailed {
            hasFailed = true
            try Data("hello".utf8).write(to: partialURL)
            throw URLError(.networkConnectionLost)
        }
        var payload = try Data(contentsOf: partialURL)
        payload.append(Data(" world".utf8))
        try payload.write(to: directory.appendingPathComponent("media.m4a"))
        try FileManager.default.removeItem(at: partialURL)
        return DownloadedWebMediaArtifact(relativeMediaPath: "media.m4a", mimeType: "audio/mp4",
                                          byteCount: Int64(payload.count))
    }
}

private struct PendingMetadataFixture: Codable {
    let id: String
    let mediaInfo: WebMediaInfo
    let storageScope: WebMediaOfflineStorageScope
    let retentionPolicy: WebMediaRetentionPolicy
    let resolvedMedia: ResolvedWebMediaSnapshot
    let state: WebMediaDownloadState
    let createdAt: Date
    let updatedAt: Date
    let downloadedAt: Date?
    let progress: WebMediaDownloadProgress?
    let failureDescription: String?
    let mediaRelativePath: String?
    let thumbnailRelativePath: String?
    let byteCount: Int64?
    let thumbnailRequest: WebMediaThumbnailRequest
    var downloadAttemptIdentifier: UUID? = nil
}

private func makeStoredMediaIdentifier(for item: WebMediaInfo) -> String {
    let digest = SHA256.hash(data: Data(item.resourceLookupKey.utf8))
    return digest.compactMap { String(format: "%02x", $0) }.joined()
}

private func makeLegacyStoredMediaIdentifier(for item: WebMediaInfo) -> String {
    let digest = SHA256.hash(data: Data(item.candidateLookupKey.utf8))
    return digest.compactMap { String(format: "%02x", $0) }.joined()
}

private func matchingFragmentItem(from item: WebMediaInfo) -> WebMediaInfo {
    var sourceComponents = URLComponents(string: item.src)
    sourceComponents?.fragment = "matching"
    return WebMediaInfo(
        name: item.name,
        src: sourceComponents?.string ?? item.src,
        pageSrc: item.pageSrc,
        pageTitle: item.pageTitle,
        mimeType: item.mimeType,
        duration: item.duration,
        detected: item.detected,
        tagId: item.tagId,
        isInvisible: item.isInvisible
    )
}

private func resolvedMedia(for item: WebMediaInfo) -> ResolvedWebMedia {
    ResolvedWebMedia(
        mediaInfo: item,
        url: URL(string: item.src)!,
        mimeType: item.normalizedMimeType,
        requestHeaders: [:],
        resolutionMethod: .direct
    )
}

private func writeLegacyMetadata(
    for item: WebMediaInfo,
    identifier: String,
    state: WebMediaDownloadState,
    rootURL: URL,
    downloadedAt: Date? = nil,
    mediaRelativePath: String? = nil
) throws {
    let directory = rootURL
        .appendingPathComponent("transient", isDirectory: true)
        .appendingPathComponent(identifier, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = Date()
    try writeMetadataFixture(
        PendingMetadataFixture(
            id: identifier,
            mediaInfo: item,
            storageScope: .transient,
            retentionPolicy: .manualTransient,
            resolvedMedia: .init(media: resolvedMedia(for: item)),
            state: state,
            createdAt: now,
            updatedAt: now,
            downloadedAt: downloadedAt,
            progress: state == .queued
                ? .init(id: identifier, fractionCompleted: 0, bytesDownloaded: 0, totalBytesExpected: nil)
                : nil,
            failureDescription: state == .failed ? "Legacy failure" : nil,
            mediaRelativePath: mediaRelativePath,
            thumbnailRelativePath: nil,
            byteCount: mediaRelativePath == nil ? nil : 6,
            thumbnailRequest: .none
        ),
        to: directory
    )
}

private func writeMetadataFixture(_ metadata: PendingMetadataFixture, to directory: URL) throws {
    let data = try JSONEncoder().encode(metadata)
    try data.write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
