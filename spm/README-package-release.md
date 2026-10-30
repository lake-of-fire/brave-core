# SwiftBrave package/release correspondence

The canonical manual-only `release-binary.yml` and `Scripts/release_package.py`
are copied into SwiftBrave by `make-spm`. Source integration does not authorize a
release. A later authorized workflow dispatch supplies a required full SHA40
`brave_core_commit` from `lake-of-fire/brave-core`. SwiftBrave is checked out at
`github.sha`; both HEAD commit objects and clean tracked index/worktree state are
verified. There is no floating ref, archive fallback, automatic push trigger, or
branch update.

The prepare job has read permission. The helper creates a fresh
`RUNNER_TEMP/swift-brave-release-*/swift-brave` stage, generates with
`make-spm STAGE --skip-build --skip-tests`, and compares it against every tracked
SwiftBrave HEAD blob and executable mode using `git ls-tree` / `git show`. Missing
and extra files, symlinks, submodules, source/resource/test/control changes, and
metadata changes fail before compilation or any artifact upload. This includes
`.gitignore`, `Package.resolved`, Documentation, README, AGENTS, Scripts, workflows,
WebMedia, and the copied native/Rust sources. There are no metadata exclusions.
**Parent integration must canonicalize all of these inputs before dispatch.**
`Package.resolved` is required to match exactly; it is not a generated-build-input
exception.

Only the single named `BraveAdblockCore` binary target declaration is normalized.
Its accepted shapes are the exact local path
`Binary/BraveAdblockCore.xcframework`, or a GitHub HTTPS release URL and lowercase
SHA256 checksum. A balanced lexer skips comments/strings and nested calls; missing,
duplicate, computed or unexpected target shapes fail closed. All bytes outside
that call, including other manifest dependencies and whitespace, must match.

After parity, `make-spm STAGE --build-only --skip-tests` builds that existing stage
without regeneration. This requires the parent-owned generator's `--build-only`
implementation. A second correspondence check guards all tracked inputs again.
Only `Binary/` and `Sources/BraveAdblockRust/target/` are post-build output trees;
tracked entries in those trees are forbidden. The one additional untracked file
allowed is `Sources/BraveAdblockRust/Cargo.lock`, recorded with its full content
and SHA256 as a resolved build input. A tracked Rust lock still must match HEAD.
Tracked Brave-core changes, including tracked CXX locks, remain forbidden.

Provenance includes exact commits, repository, Rust lock, all available CXX
manifest/workspace-ancestor locks, toolchain version outputs (`rustc`, `cargo`,
`swift`, Xcode and clang++), invoked command argv, input signature and archive
SHA256/SwiftPM checksum. macOS-14 and Rust stable still resolve moving tools and
registry dependencies. This is **not hermetic or reproducible Rust resolution**.
The tag includes full SHA256 values for canonical resolved inputs and archive
payload. The publication job alone has `contents: write`; after validating assets,
it atomically creates a new tag ref and creates a new release. Any occupied tag
fails, even for identical inputs, with no release/asset update. An interrupted
publication may leave a tag or partial release requiring coordinator inspection;
rerunning does not overwrite it.

Assets are `BraveAdblockCore.xcframework.zip`,
`BraveAdblockCore.xcframework.checksum`, `provenance.json` and a proposed
`Package.swift`. The workflow does not commit or push that manifest. A release
coordinator must review and select it separately; the currently committed binary
URL/checksum stays unchanged until then. Source correspondence does not establish
native adblock/WebMedia/Reader behavior, architecture slices, deployment targets,
linking/size, signing or distribution qualification. Those remain separate work;
no new boolean release gate claims to replace them.

Archive construction raises traversal/read errors and rejects filesystem symlinks
and nonregular entries. Before emitting metadata, and again before publication's
first remote write, `validate_xcframework_archive(path)` reads the ZIP without
extraction, checks member integrity, names, roots and file types, and checks root
`Info.plist` library/header declarations against nonempty regular members. A failed
prepare retains its stage and partial archive output. These container checks do
not verify native architectures, ABI, actual platform coverage or signing.

CLI (Python standard library):

```
python3 Scripts/release_package.py verify-checkout --repo DIR --commit SHA40
python3 Scripts/release_package.py compare --package DIR --swift-commit SHA40 --stage STAGE [--after-build]
python3 Scripts/release_package.py prepare --package DIR --core CORE --swift-commit SHA40 --brave-commit SHA40 --repository OWNER/REPO --output RUNNER_TEMP/FRESH_ASSETS
python3 Scripts/release_package.py publish --assets ASSETS --repository OWNER/REPO --swift-commit SHA40 --package DIR
```

`prepare` requires `RUNNER_TEMP` outside both source checkouts. On success it moves
only its own uniquely named stage to `~/.Trash` (recovery, not freed disk space);
release assets remain for upload. On failure the stage and any captured command
failure remain on the runner and their path is printed; hosted runner evidence
expires with the runner. No shared caches are created. Publication takes argv as
data and credentials only through `GH_TOKEN`, never through provenance/command
arguments. The helper does not print tool or command outputs containing tokens.

Portable fixture checks are maintained in
`Tests/ReleasePackaging/test_release_package.py`. Run them only through the
separately authorized portable executor; they mock native generation/build calls.
A YAML-aware review must also verify the dispatch schema, fixed checkout refs,
permission separation, environment-to-argv handling, upload-after-parity ordering,
and absence of branch writes; implementation source-string tests are inappropriate.
Generation-only real package comparison and native qualification remain distinct.

Publication rechecks the clean selected package commit and compares the entire proposed manifest with that commit after changing only the admitted binary target. A self-consistent binary declaration does not authorize other product or dependency changes.
