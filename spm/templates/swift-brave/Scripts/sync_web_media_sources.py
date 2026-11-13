#!/usr/bin/env python3

from __future__ import annotations

import shutil
import sys
from pathlib import Path
import re


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BRAVE_CORE_ROOT = REPO_ROOT.parent / "brave-core" / "ios" / "brave-ios" / "Sources" / "Brave" / "Frontend"
DESTINATION_ROOT = REPO_ROOT / "Sources" / "WebMedia" / "Resources"

SOURCE_MAP = {
    DEFAULT_BRAVE_CORE_ROOT / "UserContent" / "UserScripts" / "__firefox__.js":
        DESTINATION_ROOT / "UserScripts" / "__firefox__.js",
    DEFAULT_BRAVE_CORE_ROOT / "UserContent" / "UserScripts" / "Scripts_Dynamic" / "Scripts" / "Paged" / "PlaylistScript.js":
        DESTINATION_ROOT / "UserScripts" / "WebMediaDetectorScript.js",
    DEFAULT_BRAVE_CORE_ROOT / "UserContent" / "UserScripts" / "Scripts_Dynamic" / "Scripts" / "Paged" / "PlaylistSwizzlerScript.js":
        DESTINATION_ROOT / "UserScripts" / "WebMediaSwizzlerScript.js",
}

IDENTIFIER_REWRITE_MAP = {
    "PlaylistInfo": "WebMediaInfo",
    "MediaInfo": "WebMediaInfo",
    "PlaylistMediaKind": "WebMediaKind",
    "MediaKind": "WebMediaKind",
    "PlaylistContainerKind": "WebMediaContainerKind",
    "MediaContainerKind": "WebMediaContainerKind",
    "PlaylistPlaybackKind": "WebMediaPlaybackKind",
    "MediaPlaybackKind": "WebMediaPlaybackKind",
    "PlaylistLibrary": "WebMediaLibrary",
    "MediaLibrary": "WebMediaLibrary",
    "PlaylistWebLoaderFactory": "WebMediaLoaderFactory",
    "MediaWebLoaderFactory": "WebMediaLoaderFactory",
    "PlaylistWebLoader": "WebMediaLoader",
    "MediaWebLoader": "WebMediaLoader",
    "PlaylistMediaRequestContext": "WebMediaRequestContext",
    "MediaRequestContext": "WebMediaRequestContext",
    "PlaylistMediaResolutionMethod": "WebMediaResolutionMethod",
    "MediaResolutionMethod": "WebMediaResolutionMethod",
    "PlaylistResolvedMedia": "ResolvedWebMedia",
    "ResolvedMedia": "ResolvedWebMedia",
    "PlaylistMediaStreamer": "WebMediaStreamer",
    "MediaStreamer": "WebMediaStreamer",
    "PlaylistMimeTypeDetector": "WebMediaMimeTypeDetector",
    "MediaMimeTypeDetector": "WebMediaMimeTypeDetector",
    "PlaylistOfflineStorageScope": "WebMediaOfflineStorageScope",
    "OfflineMediaStorageScope": "WebMediaOfflineStorageScope",
    "PlaylistRetentionPolicy": "WebMediaRetentionPolicy",
    "MediaRetentionPolicy": "WebMediaRetentionPolicy",
    "PlaylistDownloadState": "WebMediaDownloadState",
    "MediaDownloadState": "WebMediaDownloadState",
    "PlaylistStoredMediaState": "StoredWebMediaState",
    "StoredMediaState": "StoredWebMediaState",
    "PlaylistDownloadProgress": "WebMediaDownloadProgress",
    "MediaDownloadProgress": "WebMediaDownloadProgress",
    "PlaylistDownloadEventKind": "WebMediaDownloadEventKind",
    "MediaDownloadEventKind": "WebMediaDownloadEventKind",
    "PlaylistDownloadEvent": "WebMediaDownloadEvent",
    "MediaDownloadEvent": "WebMediaDownloadEvent",
    "PlaylistThumbnailLoadingPolicy": "WebMediaThumbnailLoadingPolicy",
    "MediaThumbnailLoadingPolicy": "WebMediaThumbnailLoadingPolicy",
    "PlaylistThumbnailRequest": "WebMediaThumbnailRequest",
    "MediaThumbnailRequest": "WebMediaThumbnailRequest",
    "PlaylistResolvedMediaSnapshot": "ResolvedWebMediaSnapshot",
    "ResolvedMediaSnapshot": "ResolvedWebMediaSnapshot",
    "PlaylistStoredMedia": "StoredWebMedia",
    "StoredMedia": "StoredWebMedia",
    "PlaylistDownloadRecord": "WebMediaDownloadRecord",
    "MediaDownloadRecord": "WebMediaDownloadRecord",
    "PlaylistOfflineStoreError": "WebMediaOfflineStoreError",
    "OfflineMediaStoreError": "WebMediaOfflineStoreError",
    "PlaylistArtifactDownloading": "WebMediaArtifactDownloading",
    "MediaArtifactDownloading": "WebMediaArtifactDownloading",
    "PlaylistDownloadedArtifact": "DownloadedWebMediaArtifact",
    "DownloadedMediaArtifact": "DownloadedWebMediaArtifact",
    "PlaylistAssetDownloader": "WebMediaAssetDownloader",
    "MediaAssetDownloader": "WebMediaAssetDownloader",
    "PlaylistHLSAssetDownloading": "WebMediaHLSAssetDownloading",
    "HLSAssetDownloading": "WebMediaHLSAssetDownloading",
    "PlaylistHLSAssetDownloader": "WebMediaHLSAssetDownloader",
    "HLSAssetDownloader": "WebMediaHLSAssetDownloader",
    "PlaylistOfflineMediaStore": "WebMediaOfflineStore",
    "OfflineMediaStore": "WebMediaOfflineStore",
    "PlaylistStoredMediaMetadata": "StoredWebMediaMetadata",
    "StoredMediaMetadata": "StoredWebMediaMetadata",
    "PlaylistStoredMediaThumbnailStore": "StoredWebMediaThumbnailStore",
    "StoredMediaThumbnailStore": "StoredWebMediaThumbnailStore",
    "PlaylistStoredMediaFileSystem": "StoredWebMediaFileSystem",
    "StoredMediaFileSystem": "StoredWebMediaFileSystem",
    "PlaylistScriptError": "WebMediaScriptError",
    "MediaScriptError": "WebMediaScriptError",
    "PlaylistScriptConfiguration": "WebMediaScriptConfiguration",
    "MediaScriptConfiguration": "WebMediaScriptConfiguration",
    "PlaylistBuiltScriptSet": "WebMediaBuiltScriptSet",
    "MediaBuiltScriptSet": "WebMediaBuiltScriptSet",
    "PlaylistScriptEngine": "WebMediaScriptEngine",
    "MediaScriptEngine": "WebMediaScriptEngine",
    "PlaylistReadyState": "WebMediaReadyState",
    "MediaReadyState": "WebMediaReadyState",
    "PlaylistPlaybackEventName": "WebMediaPlaybackEventName",
    "MediaPlaybackEventName": "WebMediaPlaybackEventName",
    "PlaylistPlaybackPresentationMode": "WebMediaPlaybackPresentationMode",
    "MediaPlaybackPresentationMode": "WebMediaPlaybackPresentationMode",
    "PlaylistPlaybackSnapshot": "WebMediaPlaybackSnapshot",
    "MediaPlaybackSnapshot": "WebMediaPlaybackSnapshot",
    "PlaylistPlaybackEvent": "WebMediaPlaybackEvent",
    "MediaPlaybackEvent": "WebMediaPlaybackEvent",
    "PlaylistScriptMessage": "WebMediaScriptMessage",
    "MediaScriptMessage": "WebMediaScriptMessage",
    "PlaylistScriptMessageDecoder": "WebMediaScriptMessageDecoder",
    "MediaScriptMessageDecoder": "WebMediaScriptMessageDecoder",
    "PlaylistWebScriptSet": "WebMediaScriptSet",
    "MediaWebScriptSet": "WebMediaScriptSet",
    "PlaylistWebScripts": "WebMediaScripts",
    "MediaWebScripts": "WebMediaScripts",
    "PlaylistWebMessageDecoder": "WebMediaMessageDecoder",
    "MediaWebMessageDecoder": "WebMediaMessageDecoder",
    "PlaylistCandidateSelector": "WebMediaCandidateSelector",
    "MediaCandidateSelector": "WebMediaCandidateSelector",
    "PlaylistRequestContextBuilder": "WebMediaRequestContextBuilder",
    "MediaRequestContextBuilder": "WebMediaRequestContextBuilder",
    "MediaCaptureMediaKind": "WebMediaCaptureMediaKind",
    "MediaCapturePlaybackKind": "WebMediaCapturePlaybackKind",
    "MediaCaptureReadyState": "WebMediaCaptureReadyState",
    "MediaCapturePlaybackEventName": "WebMediaCapturePlaybackEventName",
    "MediaCapturePlaybackPresentationMode": "WebMediaCapturePlaybackPresentationMode",
    "MediaCapturePlaybackSnapshot": "WebMediaCapturePlaybackSnapshot",
    "MediaCapturePlaybackEvent": "WebMediaCapturePlaybackEvent",
    "MediaCaptureScriptConfiguration": "WebMediaCaptureScriptConfiguration",
    "MediaCaptureResolutionMethod": "WebMediaCaptureResolutionMethod",
    "MediaCaptureCandidate": "WebMediaCaptureCandidate",
    "MediaCaptureResolvedMedia": "WebMediaCaptureResolvedMedia",
    "MediaCaptureRequestContext": "WebMediaCaptureRequestContext",
    "MediaCaptureWebScriptSet": "WebMediaCaptureWebScriptSet",
    "MediaCaptureMessage": "WebMediaCaptureMessage",
    "MediaCaptureWebScripts": "WebMediaCaptureWebScripts",
    "MediaCaptureMessageDecoder": "WebMediaCaptureMessageDecoder",
    "MediaCaptureCandidateSelector": "WebMediaCaptureCandidateSelector",
    "MediaCaptureRequestContextBuilder": "WebMediaCaptureRequestContextBuilder",
    "MediaCaptureStorageScope": "WebMediaCaptureStorageScope",
    "MediaCaptureRetentionPolicy": "WebMediaCaptureRetentionPolicy",
    "MediaCaptureDownloadProgress": "WebMediaCaptureDownloadProgress",
    "MediaCaptureStoredMedia": "WebMediaCaptureStoredMedia",
    "MediaCaptureLibrary": "WebMediaCaptureLibrary",
    "MediaCaptureDownloadedMedia": "WebMediaCaptureDownloadedMedia",
    "MediaCaptureDownloader": "WebMediaCaptureDownloader",
}

CANONICAL_FILE_CANDIDATES = {
    "WebMediaCaptureSupport.swift": ["WebMediaCaptureSupport.swift", "MediaCaptureSupport.swift"],
    "WebMediaInfo.swift": ["WebMediaInfo.swift", "MediaInfo.swift", "PlaylistInfo.swift"],
    "WebMediaLibrary.swift": ["WebMediaLibrary.swift", "MediaLibrary.swift", "PlaylistLibrary.swift"],
    "WebMediaStreamer.swift": ["WebMediaStreamer.swift", "MediaStreamer.swift", "PlaylistMediaStreamer.swift"],
    "WebMediaMimeTypeDetector.swift": ["WebMediaMimeTypeDetector.swift", "MediaMimeTypeDetector.swift", "PlaylistMimeTypeDetector.swift"],
    "WebMediaOfflineStore.swift": ["WebMediaOfflineStore.swift", "PlaylistOfflineMediaStore.swift"],
    "WebMediaScriptEngine.swift": ["WebMediaScriptEngine.swift", "MediaScriptEngine.swift", "PlaylistScriptEngine.swift"],
    "WebMediaScriptMessage.swift": ["WebMediaScriptMessage.swift", "MediaScriptMessage.swift", "PlaylistScriptMessage.swift"],
    "WebMediaSupport.swift": ["WebMediaSupport.swift", "MediaWebSupport.swift", "PlaylistWebSupport.swift"],
}

TEXT_REWRITE_PATHS = [
    REPO_ROOT / "README.md",
    REPO_ROOT / "Tests" / "WebMediaTests" / "WebMediaTests.swift",
]

SWIFT_SOURCE_ROOT = REPO_ROOT / "Sources" / "WebMedia"

SCRIPT_REWRITE_MAP = {
    'includeOnce("Playlist"': 'includeOnce("WebMedia"',
    "$<playlistLongPressed>": "$<webMediaLongPressed>",
    "$<playlistProcessDocumentLoad>": "$<webMediaProcessDocumentLoad>",
}


def rewrite_text(text: str) -> str:
    for source, destination in sorted(IDENTIFIER_REWRITE_MAP.items(), key=lambda item: len(item[0]), reverse=True):
        text = re.sub(rf"\b{re.escape(source)}\b", destination, text)
    return text


def rewrite_file(path: Path) -> None:
    original = path.read_text()
    rewritten = rewrite_text(original)
    if rewritten != original:
        path.write_text(rewritten)
        print(f"rewrote {path}")


def rewrite_script_file(path: Path) -> None:
    original = path.read_text()
    rewritten = original
    for source, destination in SCRIPT_REWRITE_MAP.items():
        rewritten = rewritten.replace(source, destination)
    if rewritten != original:
        path.write_text(rewritten)
        print(f"rewrote script {path}")


def rename_overlay_files() -> None:
    for canonical_name, candidates in CANONICAL_FILE_CANDIDATES.items():
        canonical_path = SWIFT_SOURCE_ROOT / canonical_name
        chosen_source: Path | None = None

        for candidate_name in candidates:
            candidate_path = SWIFT_SOURCE_ROOT / candidate_name
            if not candidate_path.exists():
                continue
            chosen_source = candidate_path
            break

        if chosen_source is not None and chosen_source != canonical_path:
            if canonical_path.exists():
                canonical_path.unlink()
            chosen_source.rename(canonical_path)
            print(f"renamed {chosen_source} -> {canonical_path}")

        for candidate_name in candidates:
            candidate_path = SWIFT_SOURCE_ROOT / candidate_name
            if candidate_path == canonical_path:
                continue
            if candidate_path.exists():
                candidate_path.unlink()
                print(f"removed compatibility source {candidate_path}")


def main() -> int:
    missing = [path for path in SOURCE_MAP if not path.exists()]
    if missing:
        print("Missing Brave sources:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 1

    for source, destination in SOURCE_MAP.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        rewrite_script_file(destination)
        print(f"synced {source} -> {destination}")

    for stale_resource in [
        DESTINATION_ROOT / "UserScripts" / "PlaylistScript.js",
        DESTINATION_ROOT / "UserScripts" / "PlaylistSwizzlerScript.js",
    ]:
        if stale_resource.exists():
            stale_resource.unlink()
            print(f"removed stale generated resource {stale_resource}")

    rename_overlay_files()

    for path in sorted(SWIFT_SOURCE_ROOT.glob("*.swift")):
        rewrite_file(path)

    for path in TEXT_REWRITE_PATHS:
        if path.exists():
            rewrite_file(path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
