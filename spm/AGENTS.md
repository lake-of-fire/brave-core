# SwiftBrave generation and patches

- `make-spm` delegates to `spm/make_spm.py`: clear output, copy `templates/swift-brave`, copy upstream adblock sources, apply `patches/*.patch` in filename order, then optional build/tests. Preserve all local edits before generation.
- WebMedia's durable Swift/resource/test inputs live under `templates/swift-brave/{Sources/WebMedia,Tests/WebMediaTests}`. Edit those templates, then reconcile the generated package. Use ordered patches for copied upstream adblock source.
- The template Package.swift uses the locally built XCFramework path. Release tooling rewrites only that binary target to its published URL/checksum; do not confuse package generation with a binary release.
- Keep generated-output and canonical-input PRs linked. Preserve newer local work and upstream license/provenance notices. Updating Brave alone does not fix the custom retention/storage layer.
- Follow the current task's verification limits. Report generation, compilation and runtime checks separately. Keep the generated AGENTS.md template aligned with this workflow.

- Release preparation stages a fresh `swift-brave` directory from an explicit resolved core commit and compares the complete generated package with the selected output commit before building or publishing. `--build-only` builds that existing stage without clearing/copying/patching its source again. `--skip-build --skip-tests` performs generation only. Replaced task-owned generated paths move to `~/.Trash`.
- The manual release workflow publishes immutable assets and a proposed manifest; it does not push a default-branch manifest update. Preserve the selected binary URL/checksum until a separate release decision. Package correspondence, compiled native behavior and previous binary provenance remain separate obligations.
