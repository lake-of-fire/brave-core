# SwiftBrave

Swift Package for a trimmed Brave-derived adblock and media-capture stack.

## WebMedia

`WebMedia` is the storage-free/webview-neutral extraction layer plus a hidden offline media store.

It currently provides:

- media detector/swizzler scripts derived from Brave
- message decoding and candidate selection
- direct URL vs hidden-webview fallback media resolution
- hidden offline media downloads for file and HLS media
- persistent vs transient storage scopes
- explicit stored-media states for queued/downloading/stored/failed/cancelled + scope
- retention policies for persistent, manual transient, page-bound, and session-bound media
- persisted in-progress download records
- explicit download control APIs for query/cancel/retry
- async download event streams for state/progress observation
- relaunch restore for queued/downloading items
- resumable direct-file downloads when a partial file is available
- transient quota/eviction policy
- stored-media lookup by item or page URL, including a preferred page-level result
- eager or lazy local thumbnail storage

It intentionally does **not** include playlist UI, folders, CoreData models, toasts, or any user-visible file exposure.

### Core types

- `WebMediaScripts`
- `WebMediaMessageDecoder`
- `WebMediaCandidateSelector`
- `WebMediaStreamer`
- `WebMediaOfflineStore`
- `WebMediaLibrary`

### Storage model

Offline media is stored only under app-managed roots:

- persistent: Application Support
- transient: Caches

The package marks these roots as excluded from backup by default and does not expose a user-facing share/export API.

### Download model

There are two layers:

1. `WebMediaStreamer`
   Resolves a `WebMediaInfo` into a playable/downloadable `ResolvedWebMedia`.

2. `WebMediaOfflineStore`
   Stores resolved media, keeps per-item metadata, tracks download state, restores unfinished downloads on launch, and manages hidden files.

`WebMediaLibrary` composes both layers for app code that wants a single façade.

### Download control model

The store/library also expose:

- `isDownloading(id:)`
- `cancelDownload(id:)`
- `retryDownload(id:)`
- `downloadEvents(id:)`

This is the intended minimal control surface for Manabi/LakeOfFire before any playlist-management UI exists.

### Retention and state model

`WebMediaDownloadRecord` and `StoredWebMedia` both expose:

- `storedMediaState`
- `storageScope`
- `retentionPolicy`

Use them as follows:

- `storageScope: .transient` + `retentionPolicy: .untilPageChange`
  Download the full file for current-page playback/transcription and drop it after the page changes.
- `storageScope: .transient` + `retentionPolicy: .untilSessionEnds`
  Keep the full file until app/session cleanup.
- `storageScope: .transient` + `retentionPolicy: .manualTransient`
  Keep the file in hidden transient storage until your own cleanup policy removes it.
- `storageScope: .persistent` + `retentionPolicy: .persistent`
  User explicitly chose offline save.

You can later promote or demote retention with `updateRetentionPolicy(...)` without building UI concepts into this package.

### Thumbnail model

`WebMediaThumbnailRequest` supports:

- `.automatic()`
  Eager for media-derived thumbnails, lazy when a separate remote thumbnail URL would require extra network work.
- `.lazy(...)`
  Defer thumbnail generation/fetch until `ensureThumbnail(id:)`.
- `.none`
  Skip thumbnail work entirely.

This keeps media download latency separate from thumbnail fetch latency when the thumbnail is optional.

### Recommended integration for LakeOfFire / Manabi

1. Detect candidates from the visible webview with `WebMediaScripts` and `WebMediaMessageDecoder`.
2. Pick the preferred candidate with `WebMediaCandidateSelector`.
3. When the user wants playback/transcription/download behavior, call `WebMediaLibrary.enqueueDownload(...)` or `WebMediaLibrary.download(...)`.
4. Use `.transient` plus `.untilPageChange` or `.untilSessionEnds` when the media is only needed for the current page/session.
5. Use `.persistent` when the user explicitly chooses offline save.
6. On app launch, call `WebMediaLibrary.restorePendingDownloads()` to restart queued/downloading items.
7. On navigation changes, use `WebMediaLibrary.deleteTransientMedia(forPageURL:)` or `WebMediaLibrary.purgeTransientMedia(exceptPageURLs:)`.
8. When a transient item should be kept, call `WebMediaLibrary.updateRetentionPolicy(.persistent, for: id)` or `WebMediaLibrary.updateStorageScope(.persistent, for: id)`.
9. When UI needs artwork later, call `WebMediaLibrary.ensureThumbnail(id:)` instead of forcing thumbnail work into the initial download path.
10. When the page changes, call `WebMediaLibrary.handlePageDidChange(from:to:)`.
11. When the app/session ends, call `WebMediaLibrary.handleSessionDidEnd()`.

### APIs you will likely use next in Manabi

```swift
let library = WebMediaLibrary(
    mediaStreamer: WebMediaStreamer(
        urlSession: .shared,
        webLoaderFactory: yourHiddenWebLoaderFactory
    ),
    offlineStore: WebMediaOfflineStore()
)

let record = try await library.enqueueDownload(
    candidate,
    requestContext: requestContext,
    storageScope: .transient,
    retentionPolicy: .untilPageChange,
    thumbnail: .automatic()
)

let stored = try await library.waitForDownload(id: record.id)
let existing = try await library.bestStoredMedia(forPageURL: pageURL)
let thumbReady = try await library.ensureThumbnail(id: stored.id)
let isDownloading = try await library.isDownloading(id: record.id)
let events = await library.downloadEvents(id: record.id)

try await library.restorePendingDownloads()
try await library.handlePageDidChange(from: previousPageURL, to: pageURL)
try await library.purgeTransientMedia(exceptPageURLs: [pageURL])
try await library.updateRetentionPolicy(.persistent, for: stored.id)
```

### Notes

- File downloads use a direct request path.
- HLS downloads use `AVAssetDownloadURLSession`.
- Relaunch restore currently re-enqueues unfinished downloads from persisted metadata. For direct file downloads, the downloader resumes from `media.partial` when that file exists; otherwise it restarts cleanly.
- DRM/Widevine/FairPlay media remains unsupported.
- Subtitle extraction is intentionally out of scope here.

- Run `../brave-core/make-spm /path/to/swift-brave` to regenerate locally.
- CI release: use the `release-binary` workflow to build a zip + checksum for the
  `BraveAdblockCore.xcframework` binary target.

## Durable source of truth

WebMedia source, resources, and tests are maintained in `brave-core/spm/templates/swift-brave`. Make changes there and reconcile the generated output; do not run `make-spm` on a dirty destination. The generator clears its output directory. The offline durability reconciliation preserves the October 6 local attempt-ID/staging changes; verification is still required before integration.
