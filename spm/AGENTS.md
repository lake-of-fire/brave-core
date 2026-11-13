# SwiftBrave generation and patches

- `make-spm` delegates to `spm/make_spm.py`: clear output, copy `templates/swift-brave`, copy upstream adblock sources, apply `patches/*.patch` in filename order, then optional build/tests. Preserve all local edits before generation.
- WebMedia's durable Swift/resource/test inputs live under `templates/swift-brave/{Sources/WebMedia,Tests/WebMediaTests}`. Edit those templates, then reconcile the generated package. Use ordered patches for copied upstream adblock source.
- The template Package.swift uses the locally built XCFramework path. Release tooling rewrites only that binary target to its published URL/checksum; do not confuse package generation with a binary release.
- Keep generated-output and canonical-input PRs linked. Preserve newer local work and upstream license/provenance notices. Updating Brave alone does not fix the custom retention/storage layer.
- Follow the current task's verification limits. Report generation, compilation and runtime checks separately. Keep the generated AGENTS.md template aligned with this workflow.
