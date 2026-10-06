# Generated SwiftBrave package

- `../brave-core/make-spm` regenerates this package: it clears the destination, copies `spm/templates/swift-brave`, copies upstream sources, then applies `spm/patches/*.patch` in filename order. Preserve local changes before regeneration.
- Make durable fixes in the matching template, overlay or patch in the **actual brave-core checkout**, then reconcile the generated SwiftBrave change. An output-only edit may disappear on the next generation.
- `Scripts/sync_web_media_sources.py` copies Brave JavaScript resources and normalizes existing Swift overlays; it does not establish the source of the WebMedia offline store. Locate the real media template/overlay before editing it. If it is missing from the published generator, do not invent its provenance or replace newer local work.
- Record the input branch/commit and link source-side and generated-output PRs. Compare upstream fixes before copying them; retain required license/provenance notices and custom WebMedia behavior.
- Follow the current task's build/test limits. Distinguish code changes, successful generation and runtime verification; never label unrun checks as passed.
