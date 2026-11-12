# Reconciled WebMedia offline durability changes

## Source of truth and preserved work

This revision reconciles the five offline-download fixes with the actual October 6 local SwiftBrave snapshot, instead of replacing it with the older published file. The snapshot's base was `84f2ba37df3992db73f62b99a3389cee886cbce5`; the original offline-store SHA-256 was `c0692fd5985018f0f3032b75610e628374c69c7598b2e995db8f83d52a9340a4`.

The local changes in WebMediaInfo.swift and WebMediaLibrary.swift are preserved unchanged. The existing staged download attempts, UUID ownership fences, cancellation-aware waiters, thumbnail ownership, partial recovery and physical-root normalization are retained in WebMediaOfflineStore.swift. Existing local tests are retained; HTTP-resume fixtures now provide a strong representation validator. Two additional regressions cover changed ETags and preservation of unreadable persistent metadata. None of the tests have been run in this task.

The canonical source is now represented in the companion [brave-core draft PR #1](https://github.com/lake-of-fire/brave-core/pull/1): `spm/templates/swift-brave/Sources/WebMedia`, its resources, `Tests/WebMediaTests`, the sync script, and the WebMedia package target/dependency. The generated-output companion is [swift-brave draft PR #1](https://github.com/lake-of-fire/swift-brave/pull/1).

The generator is `make-spm` → `spm/make_spm.py`: clear output except .git/.gitignore, copy templates, copy upstream adblock sources, apply ordered patches, then optional build/tests. Do not run it over a dirty package. The template manifest retains the local generated package's Swift 6.2 and platform/product/dependency shape while using the generator's existing local XCFramework target path. No binary was rebuilt or release checksum changed.

## Five corrections

1. Each HLS invocation owns a serial operation queue, cancellation latch, session/task identity and exactly-once continuation completion. Late callbacks cannot finish a reused downloader's new operation.
2. Partial file resume requires a saved strong ETag, request fingerprint, final response URL and compatible total size. It uses If-Range and identity encoding, validates Content-Range, and checks body size. Unknown-total responses require the saved validator's known total. Invalid tails do not publish a final artifact; completed malformed range bodies roll back to the original prefix. Legacy partials without valid identity restart.
3. The final downloaded metadata write is the commit point. Optional cache maintenance cannot send an already committed download through destructive failure handling.
4. Metadata read/decode errors preserve the original directory and propagate rather than deleting uncertain data.
5. Scope/retention changes atomically persist target scope and the exact requested retention policy before moving. Recovery uses that intent from either location, preserves conflicting copies, and clears intent only after destination metadata commits. Existing completed-only preconditions and active-writer exclusion remain.

The resume identity sidecar travels with partial bytes through the local attempt staging/recovery paths. Destination identity is removed before replacing bytes, so a crash between the two file moves cannot combine a new prefix with an old validator. Missing identity safely causes a fresh download.

## Upstream comparison

Brave [#38461](https://github.com/brave/brave-core/pull/38461), merged July 29, 2026 (`aa85c139bb84ab0431c4e7490734a97f1da84ad9`), is a useful item/UUID startup-cancellation design reference. It does not prove this custom continuation-based HLS operation or all post-probe start races are safe.

Brave [#35862](https://github.com/brave/brave-core/pull/35862) reconciles stale bookmarks/missing cached files; [#38650](https://github.com/brave/brave-core/pull/38650) adds LRU reclamation. Neither supplies this custom partial-append validation or persistent/transient retention transaction model. No wholesale upstream update or blind cherry-pick was made. Existing license/provenance notices are retained.

## Deliberately unrun owner verification

Per the user's instruction, no generation, build, typecheck, lint, test or runtime verification was run for this reconciliation. The read-only Mac investigator previously ran one whitespace-only git diff check on the original worktree; that is not evidence for this changed code.

The owner should:
- Preserve and reconcile any edits newer than the captured local snapshot before integrating these draft branches. No local repository, Reader pin, generated project or coordinator was changed here.
- Reconcile the generator branch with the desired brave-core checkout. Its local `d8cf473` divergence changes unrelated SwiftUI access modifiers and was not overwritten or merged.
- Generate in an isolated disposable output directory, then compile and run the owning SwiftBrave suites.
- Exercise HLS cancellation before registration and racing completion, duplicate callbacks and concurrent downloader reuse.
- Cover validated/changed/missing/weak ETags, redirects, 200/206/416, encoded/short/long responses, and interrupted byte/sidecar transfers.
- Inject metadata/cache I/O failures around the completion commit; verify successful downloads remain intact.
- Interrupt retention transitions before/after intent, move and destination write; verify all exact retention policies, duplicate destination preservation and active-writer rejection.

This is an unqualified implementation draft, not a release or assembled Reader acceptance claim.

Canonical template publication: [brave-core 1c49cba](https://github.com/lake-of-fire/brave-core/commit/1c49cba393098e791649992155a86051c98b8e16). Reconciled runtime/test publication: [swift-brave d536171](https://github.com/lake-of-fire/swift-brave/commit/d536171c130d60260c54bf048665b20faf2b375c).
