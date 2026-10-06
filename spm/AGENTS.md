# SwiftBrave generation and patches

- `make-spm` delegates to `spm/make_spm.py`: clear destination, copy `templates/swift-brave`, copy upstream adblock sources, apply `patches/*.patch` in filename order, then optional build/tests. Do not run it over unpreserved local edits.
- Change package-owned Swift code in its canonical template/overlay; use ordered patches for copied upstream source. Reconcile the generated `swift-brave` output and link both PRs. Do not rely on output-only fixes surviving regeneration.
- Locate the actual WebMedia source of truth first. The published generator currently lacks its Swift overlay; a local generated file alone does not prove its canonical source or branch. Never replace newer local media work with an older published snapshot.
- Compare relevant Brave upstream changes and preserve provenance/license notices. Keep unrelated coordinator or application changes out of a patch-only task.
- Respect the current task's verification limits and report generation/build/tests separately. Keep `templates/swift-brave/AGENTS.md` aligned with this workflow so generated packages retain the instructions.
