"""Portable functional fixtures; no Swift/Rust compilation or external services."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[2] / "Scripts/release_package.py"
spec = importlib.util.spec_from_file_location("release_package", HELPER)
rp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rp)

LOCAL = '.binaryTarget(\n name: "BraveAdblockCore",\n path: "Binary/BraveAdblockCore.xcframework"\n)'
URL = "https://github.com/example/package/releases/download/old/BraveAdblockCore.xcframework.zip"
CHECKSUM = "a" * 64
REMOTE = f'.binaryTarget(name: "BraveAdblockCore", url: "{URL}", checksum: "{CHECKSUM}")'
PREFIX = '''// swift-tools-version: 6.2
import PackageDescription
// Unicode outside target must survive: 日本語 🍵
let ignored = #".binaryTarget(name: "BraveAdblockCore") )"#
/* nested /* .binaryTarget( */ comment */
let package = Package(name: "Fixture", products: [
 .library(name: "BraveAdblock", targets: ["BraveAdblock"]),
 .library(name: "WebMedia", targets: ["WebMedia"])
], dependencies: [.package(url: "https://example.com/dependency", branch: "main")], targets: [
'''
SUFFIX = ''',
 .target(name: "WebMedia", resources: [.process("Resources")]),
 .testTarget(name: "WebMediaTests", dependencies: [.byName(name: "WebMedia")])
])
'''


def manifest(call=LOCAL):
    return (PREFIX + call + SUFFIX).encode()


def archive_files():
    # Container fixture only: these bytes are deliberately not a native library.
    return {"Info.plist": plistlib.dumps({"AvailableLibraries": [
        {"LibraryIdentifier": "ios", "LibraryPath": "lib.a", "HeadersPath": "Headers"}]}),
        "ios/lib.a": b"fixture library bytes", "ios/Headers/core.h": b"void fixture(void);"}


def write_archive(path, files=None, extras=()):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        for name, data in (archive_files() if files is None else files).items():
            archive.writestr(rp.XCFRAMEWORK_ROOT + "/" + name, data)
        for member, data in extras:
            archive.writestr(member, data)


class ArchiveValidationTests(unittest.TestCase):
    def test_real_container_is_accepted_without_extraction(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / "fixture.zip"
            write_archive(path)
            rp.validate_xcframework_archive(path)
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_nonzip_truncation_and_crc_damage(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / "fixture.zip"
            write_archive(path)
            valid = path.read_bytes()
            with zipfile.ZipFile(path) as archive:
                library = archive.getinfo(rp.XCFRAMEWORK_ROOT + "/ios/lib.a")
                offset = library.header_offset
            name_length, extra_length = struct.unpack_from("<HH", valid, offset + 26)
            payload = offset + 30 + name_length + extra_length
            damaged = bytearray(valid)
            damaged[payload] ^= 1
            for data in (b"not a ZIP", valid[:-10], bytes(damaged)):
                path.write_bytes(data)
                with self.assertRaises(rp.PackagingError) as caught:
                    rp.validate_xcframework_archive(path)
                self.assertIsNotNone(caught.exception.__cause__)

    def test_unsafe_duplicate_root_and_special_members(self):
        root = rp.XCFRAMEWORK_ROOT
        members = ["/" + root + "/x", root + "/../x", root + "/./x",
                   root + "//x", root + "/x\\y", "C:/" + root + "/x",
                   "Other.xcframework/x", root + "/Info.plist", root]
        for mode, name in [(stat.S_IFLNK, root + "/link"),
                           (stat.S_IFIFO, root + "/fifo"),
                           (stat.S_IFDIR, root + "/disguised-file"),
                           (stat.S_IFREG, root + "/disguised-directory/")]:
            member = zipfile.ZipInfo(name)
            member.create_system = 3
            member.external_attr = (mode | 0o755) << 16
            members.append(member)
        dos_directory = zipfile.ZipInfo(root + "/dos-directory")
        dos_directory.external_attr = 0x10
        members.append(dos_directory)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / "fixture.zip"
            for member in members:
                with self.subTest(member=member), warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    write_archive(path, extras=[(member, b"x")])
                    with self.assertRaises(rp.PackagingError):
                        rp.validate_xcframework_archive(path)
            # zipfile.writestr truncates NUL names; patch the on-disk names instead.
            write_archive(path, extras=[(root + "/badXname", b"x")])
            path.write_bytes(path.read_bytes().replace(b"badXname", b"bad\0name"))
            with self.assertRaises(rp.PackagingError):
                rp.validate_xcframework_archive(path)

    def test_declared_members_and_plist_contract(self):
        cases = []
        for missing in ("Info.plist", "ios/lib.a", "ios/Headers/core.h"):
            cases.append({name: data for name, data in archive_files().items() if name != missing})
        for name in ("ios/lib.a", "ios/Headers/core.h"):
            cases.append(dict(archive_files(), **{name: b""}))
        for value in (b"bad plist", plistlib.dumps([]), plistlib.dumps({}),
                      plistlib.dumps({"AvailableLibraries": []})):
            cases.append(dict(archive_files(), **{"Info.plist": value}))
        library = {"LibraryIdentifier": "ios", "LibraryPath": "lib.a", "HeadersPath": "Headers"}
        for key, value in (("LibraryIdentifier", "../ios"), ("LibraryIdentifier", "a/b"),
                           ("LibraryPath", "/lib.a"), ("LibraryPath", "../lib.a"),
                           ("HeadersPath", ""), ("HeadersPath", "../Headers")):
            info = {"AvailableLibraries": [dict(library, **{key: value})]}
            cases.append(dict(archive_files(), **{"Info.plist": plistlib.dumps(info)}))
        cases.append(dict(archive_files(), **{"Info.plist": plistlib.dumps(
            {"AvailableLibraries": [library, library]})}))
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / "fixture.zip"
            for files in cases:
                with self.subTest(files=files):
                    write_archive(path, files)
                    with self.assertRaises(rp.PackagingError):
                        rp.validate_xcframework_archive(path)


class ManifestTests(unittest.TestCase):
    def test_only_selected_target_normalizes(self):
        self.assertEqual(rp.normalize_manifest(manifest()), rp.normalize_manifest(manifest(REMOTE)))
        for old, new in [(b'"WebMedia"', b'"Removed"'), (b'branch: "main"', b'branch: "other"'),
                         (b'.process("Resources")', b'.process("Other")'), (b'Fixture', b'Other'),
                         (b'// Unicode', b'// changed')]:
            self.assertNotEqual(rp.normalize_manifest(manifest()),
                                rp.normalize_manifest(manifest().replace(old, new)))

    def test_transform_isolated_and_repeatable(self):
        rewritten = rp.release_manifest(manifest(), URL, CHECKSUM)
        self.assertEqual(rewritten, manifest(REMOTE))
        self.assertEqual(rp.release_manifest(rewritten, URL, CHECKSUM), rewritten)
        start, end = rp.binary_span(rewritten.decode())
        args = [token[1] for token in rp.swift_tokens(rewritten.decode()[start:end])
                if token[0] == "string"]
        self.assertEqual(args, ['"BraveAdblockCore"', f'"{URL}"', f'"{CHECKSUM}"'])
        self.assertEqual(rp.normalize_manifest(rewritten), rp.normalize_manifest(manifest()))

    def test_comments_nested_calls_and_strings(self):
        call = '''.binaryTarget(/* a ( /* nested */ ) */ name: "BraveAdblockCore",
          path: /* ) */ "Binary/BraveAdblockCore.xcframework", // extra )
        )'''
        self.assertEqual(rp.normalize_manifest(manifest(call)), rp.normalize_manifest(manifest()))
        extra = '''let x = factory(nested("a)"), #"raw)"#, """multiline ( )""")
let y = "interpolated \\(f(\"inside)\"))"
'''
        for prefix in [extra, '// .binaryTarget(name: "BraveAdblockCore")\n']:
            self.assertEqual(rp.release_manifest((prefix.encode() + manifest()), URL, CHECKSUM),
                             prefix.encode() + manifest(REMOTE))

    def test_unselected_binary_target_is_preserved(self):
        other = '.binaryTarget(name: "Other", path: "Other.xcframework"),\n'
        original = manifest().replace(LOCAL.encode(), (other + LOCAL).encode())
        rewritten = rp.release_manifest(original, URL, CHECKSUM)
        self.assertEqual(rewritten, manifest().replace(LOCAL.encode(), (other + REMOTE).encode()))
        changed = rewritten.replace(b'Other.xcframework', b'Different.xcframework')
        self.assertNotEqual(rp.normalize_manifest(original), rp.normalize_manifest(changed))

    def test_invalid_or_ambiguous_target_fails(self):
        invalid = ["", LOCAL + "," + LOCAL, LOCAL + "," + REMOTE, LOCAL[:-1],
                   LOCAL.replace("BraveAdblockCore", "Other"),
                   LOCAL.replace("Binary/", "Elsewhere/"),
                   LOCAL.replace('name: "BraveAdblockCore"', 'name: makeName("BraveAdblockCore")'),
                   LOCAL.replace('path:', 'other:'),
                   LOCAL.replace('\n)', ', checksum: "x"\n)'),
                   LOCAL.replace('path:', 'name: "BraveAdblockCore", path:'),
                   LOCAL + "/* unterminated", LOCAL + '\nlet s = "unterminated']
        for call in invalid:
            with self.subTest(call=call), self.assertRaises(rp.PackagingError):
                rp.normalize_manifest(manifest(call))

    def test_remote_validation(self):
        for url, checksum in [(URL.replace("https:", "http:"), CHECKSUM),
                              (URL + "?token=secret", CHECKSUM),
                              (URL.replace("github.com", "user@github.com"), CHECKSUM),
                              (URL.replace("github.com", "evil.example"), CHECKSUM),
                              (URL, "z" * 64), (URL, "A" * 64), (URL, "a" * 63)]:
            with self.subTest(url=url), self.assertRaises(rp.PackagingError):
                rp.release_manifest(manifest(), url, checksum)


class PackageFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="release-packaging-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "committed"
        self.stage = self.root / "swift-brave"
        self.repo.mkdir()
        self.stage.mkdir()
        # Tiny genuine package with wrapper, native/Rust source, controls and resources.
        self.files = {
            "Package.swift": manifest(REMOTE),
            "Package.resolved": b'{"pins":[],"version":3}\n',
            ".gitignore": b"Binary/\nSources/BraveAdblockRust/target/\n",
            "AGENTS.md": b"Canonical fixture\n", "README.md": b"Fixture package\n",
            ".github/workflows/release-binary.yml": b"name: preserved\non: workflow_dispatch\n",
            "Scripts/control.py": b"print('fixture')\n",
            "Sources/BraveAdblock/Wrapper.swift": b"public struct Wrapper {}\n",
            "Sources/BraveAdblockCore/src/AdblockEngine.mm": b"// native wrapper\n",
            "Sources/BraveAdblockRust/src/lib.rs": b"// rust input\n",
            "Sources/WebMedia/Media.swift": b"public struct Media {}\n",
            "Sources/WebMedia/Resources/script.js": b"// resource\n",
            "Tests/WebMediaTests/MediaTests.swift": b"// fixture tests\n",
        }
        for relative, data in self.files.items():
            for directory in [self.repo, self.stage]:
                path = directory / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        (self.stage / "Package.swift").write_bytes(manifest())
        self.git("init", "--quiet")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture")
        self.commit = self.git("rev-parse", "HEAD").decode().strip()

    def git(self, *args):
        return rp.run(["git", *args], self.repo)

    def compare(self, after_build=False):
        rp.compare_package(self.repo, self.commit, self.stage, after_build)

    def test_complete_package_equal_and_head_readback(self):
        self.compare()
        self.assertEqual(set(rp.committed_files(self.repo, self.commit)), set(self.files))
        with self.assertRaises(rp.PackagingError):
            rp.verify_checkout(self.repo, "0" * 40)
        for value in ["main", "a" * 39, "a" * 40 + ";touch pwned"]:
            with self.assertRaises(rp.PackagingError):
                rp.verify_checkout(self.repo, value)

    def test_every_tracked_surface_is_guarded(self):
        for relative, data in self.files.items():
            path = self.stage / relative
            with self.subTest(path=relative), self.assertRaises(rp.PackagingError):
                path.write_bytes(data + b"// changed\n")
                self.compare()
            path.write_bytes(manifest() if relative == "Package.swift" else data)
            with self.subTest(missing=relative), self.assertRaises(rp.PackagingError):
                path.unlink()
                self.compare()
            path.write_bytes(manifest() if relative == "Package.swift" else data)

    def test_extras_and_symlinks_rejected(self):
        extra = self.stage / "Sources/WebMedia/Extra.swift"
        extra.write_text("extra")
        with self.assertRaises(rp.PackagingError):
            self.compare()
        extra.unlink()
        extra.symlink_to(self.repo / "README.md")
        with self.assertRaises(rp.PackagingError):
            self.compare()
        extra.unlink()
        extra.symlink_to(self.repo, target_is_directory=True)
        with self.assertRaises(rp.PackagingError):
            self.compare()

    def test_dirty_index_worktree_and_modes_rejected(self):
        path = self.repo / "README.md"
        path.write_text("dirty")
        with self.assertRaises(rp.PackagingError):
            self.compare()
        self.git("add", "README.md")
        path.write_bytes(self.files["README.md"])
        with self.assertRaises(rp.PackagingError):
            self.compare()
        self.git("reset", "--quiet", "HEAD", "README.md")
        (self.stage / "README.md").chmod(0o755)
        with self.assertRaises(rp.PackagingError):
            self.compare()

    def test_build_inputs_are_narrow_and_tracked_locks_stay_guarded(self):
        lock = self.stage / rp.RUST_LOCK
        lock.write_text("generated Rust lock")
        with self.assertRaises(rp.PackagingError):
            self.compare()
        binary = self.stage / "Binary/BraveAdblockCore.xcframework/lib.a"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"archive")
        target = self.stage / "Sources/BraveAdblockRust/target/cache"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"cache")
        self.compare(after_build=True)
        (self.stage / "Sources/BraveAdblockRust/Other.lock").write_text("extra")
        with self.assertRaises(rp.PackagingError):
            self.compare(after_build=True)
        (self.stage / "Sources/BraveAdblockRust/Other.lock").unlink()
        (self.repo / rp.RUST_LOCK).write_text("committed lock")
        self.git("add", rp.RUST_LOCK)
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "lock fixture")
        self.commit = self.git("rev-parse", "HEAD").decode().strip()
        with self.assertRaises(rp.PackagingError):
            self.compare(after_build=True)

    def test_correspondence_failure_prevents_build_and_assets(self):
        core = self.root / "core"
        core.mkdir()
        self.git_core = lambda *args: rp.run(["git", *args], core)
        self.git_core("init", "--quiet")
        (core / "input").write_text("fixture")
        self.git_core("add", ".")
        self.git_core("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                      "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "core fixture")
        core_commit = self.git_core("rev-parse", "HEAD").decode().strip()
        calls = []
        real_run = rp.run

        def fixture_run(argv, cwd=None):
            if str(argv[0]) == str(core / "make-spm"):
                calls.append([str(x) for x in argv])
                destination = Path(argv[1])
                shutil.copytree(self.stage, destination, dirs_exist_ok=True)
                (destination / "Sources/WebMedia/Media.swift").write_text("stale generated input")
                return b""
            return real_run(argv, cwd)

        output = self.root / "assets"
        with patch.dict(os.environ, {"RUNNER_TEMP": str(self.root)}), patch.object(rp, "run", fixture_run):
            with self.assertRaises(rp.PackagingError):
                rp.prepare_release(self.repo, core, self.commit, core_commit, "example/package", output)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][-2:], ["--skip-build", "--skip-tests"])
        self.assertEqual(list(output.iterdir()), [])


    def prepare_fixture(self, mutate_after_build=False):
        core = self.root / "build-core"
        core.mkdir()
        cxx_lock = core / "tools/crates/vendor/cxxbridge-cmd/Cargo.lock"
        cxx_lock.parent.mkdir(parents=True)
        cxx_lock.write_text("CXX resolved fixture lock")
        real_run = rp.run
        real_run(["git", "init", "--quiet"], core)
        real_run(["git", "add", "."], core)
        real_run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                  "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "core fixture"], core)
        core_commit = real_run(["git", "rev-parse", "HEAD"], core).decode().strip()
        calls = []

        def fixture_run(argv, cwd=None):
            if str(argv[0]) == str(core / "make-spm"):
                calls.append([str(x) for x in argv])
                destination = Path(argv[1])
                if "--skip-build" in argv:
                    shutil.copytree(self.stage, destination, dirs_exist_ok=True)
                else:
                    # The builder consumes the existing stage; it does not generate it.
                    self.assertEqual((destination / "Sources/WebMedia/Media.swift").read_bytes(),
                                     self.files["Sources/WebMedia/Media.swift"])
                    for name, data in archive_files().items():
                        binary = destination / "Binary/BraveAdblockCore.xcframework" / name
                        binary.parent.mkdir(parents=True, exist_ok=True)
                        binary.write_bytes(data)
                    (destination / rp.RUST_LOCK).write_text("Rust resolved fixture lock")
                    if mutate_after_build:
                        (destination / "Sources/WebMedia/Media.swift").write_text("modified by build")
                return b"fixture generator output"
            if str(argv[0]) in {"rustc", "cargo", "swift", "xcodebuild", "xcrun"}:
                return b"fixture toolchain version"
            return real_run(argv, cwd)

        home = self.root / "fixture-home"
        home.mkdir()
        return core, core_commit, calls, fixture_run, home

    def test_pipeline_builds_existing_stage_and_emits_bound_provenance(self):
        core, core_commit, calls, runner, home = self.prepare_fixture()
        output = self.root / "successful-assets"
        with patch.dict(os.environ, {"RUNNER_TEMP": str(self.root)}), patch.object(rp, "run", runner), \
                patch.object(rp.Path, "home", return_value=home):
            rp.prepare_release(self.repo, core, self.commit, core_commit, "example/package", output)
        self.assertEqual([call[2:] for call in calls],
                         [["--skip-build", "--skip-tests"], ["--build-only", "--skip-tests"]])
        self.assertEqual({path.name for path in output.iterdir()}, set(rp.ASSETS))
        with zipfile.ZipFile(output / rp.ASSETS[0]) as archive:
            self.assertEqual({name.removeprefix(rp.XCFRAMEWORK_ROOT + "/"): archive.read(name)
                              for name in archive.namelist()}, archive_files())
        provenance = json.loads((output / "provenance.json").read_text())
        self.assertEqual(provenance["inputs"]["swift_brave_commit"], self.commit)
        self.assertEqual(provenance["inputs"]["brave_core_commit"], core_commit)
        self.assertEqual(provenance["inputs"]["dependency_locks"]["package/" + rp.RUST_LOCK]["content"],
                         "Rust resolved fixture lock")
        self.assertEqual(provenance["inputs"]["dependency_locks"][
            "brave-core/tools/crates/vendor/cxxbridge-cmd/Cargo.lock"]["content"], "CXX resolved fixture lock")
        self.assertEqual(rp.release_identity(provenance["inputs"], provenance["archive_sha256"]),
                         (provenance["tag"], provenance["release_input_signature"]))
        self.assertEqual(rp.normalize_manifest((output / "Package.swift").read_bytes()),
                         rp.normalize_manifest(self.files["Package.swift"]))
        self.assertEqual(len(list((home / ".Trash").iterdir())), 1)
        self.assertEqual(list(self.root.glob("swift-brave-release-*")), [])

    def test_post_build_source_change_blocks_archive(self):
        core, core_commit, calls, runner, home = self.prepare_fixture(mutate_after_build=True)
        output = self.root / "rejected-assets"
        with patch.dict(os.environ, {"RUNNER_TEMP": str(self.root)}), patch.object(rp, "run", runner), \
                patch.object(rp.Path, "home", return_value=home):
            with self.assertRaises(rp.PackagingError):
                rp.prepare_release(self.repo, core, self.commit, core_commit, "example/package", output)
        self.assertEqual(len(calls), 2)
        self.assertEqual(list(output.iterdir()), [])
        self.assertEqual(len(list(self.root.glob("swift-brave-release-*"))), 1)

    def test_archive_walk_error_retains_stage_and_prevents_metadata_assets(self):
        core, core_commit, calls, runner, home = self.prepare_fixture()
        output = self.root / "walk-failed-assets"
        real_walk = rp.os.walk
        failure = OSError("fixture scandir failure")

        def failing_walk(top, *args, **kwargs):
            if Path(top).name == rp.XCFRAMEWORK_ROOT:
                yield str(top), [], ["Info.plist"]
                kwargs["onerror"](failure)
            else:
                yield from real_walk(top, *args, **kwargs)

        with patch.dict(os.environ, {"RUNNER_TEMP": str(self.root)}), \
                patch.object(rp, "run", runner), patch.object(rp.os, "walk", failing_walk):
            with self.assertRaises(OSError) as caught:
                rp.prepare_release(self.repo, core, self.commit, core_commit, "example/package", output)
        self.assertIs(caught.exception, failure)
        self.assertEqual(len(calls), 2)
        self.assertEqual({p.name for p in output.iterdir()}, {rp.ASSETS[0]})
        self.assertEqual(len(list(self.root.glob("swift-brave-release-*"))), 1)

    def test_archive_source_symlinks_and_nonregular_entries_fail_closed(self):
        core, core_commit, calls, runner, home = self.prepare_fixture()
        for kind in ("file-link", "directory-link", "fifo"):
            output = self.root / (kind + "-assets")

            def unsafe_builder(argv, cwd=None):
                result = runner(argv, cwd)
                if "--build-only" in argv:
                    binary = Path(argv[1]) / "Binary" / rp.XCFRAMEWORK_ROOT
                    entry = binary / "unsafe"
                    if kind == "fifo":
                        os.mkfifo(entry)
                    else:
                        entry.symlink_to(binary / ("ios" if kind == "directory-link" else "ios/lib.a"),
                                         target_is_directory=kind == "directory-link")
                return result

            with self.subTest(kind=kind), \
                    patch.dict(os.environ, {"RUNNER_TEMP": str(self.root)}), \
                    patch.object(rp, "run", unsafe_builder):
                with self.assertRaises(rp.PackagingError):
                    rp.prepare_release(self.repo, core, self.commit, core_commit, "example/package", output)
            self.assertEqual({p.name for p in output.iterdir()}, {rp.ASSETS[0]})
        self.assertEqual(len(list(self.root.glob("swift-brave-release-*"))), 3)

    def test_archive_read_failure_retains_evidence_without_metadata(self):
        core, core_commit, calls, runner, home = self.prepare_fixture()
        output = self.root / "read-failed-assets"
        failure = OSError("fixture read failure")
        copy_file = rp.shutil.copyfileobj

        def fail_archive_read(source, target, *args):
            if isinstance(source.name, int):  # fdopen used by the archive constructor
                raise failure
            return copy_file(source, target, *args)

        with patch.dict(os.environ, {"RUNNER_TEMP": str(self.root)}), \
                patch.object(rp, "run", runner), \
                patch.object(rp.shutil, "copyfileobj", side_effect=fail_archive_read):
            with self.assertRaises(OSError) as caught:
                rp.prepare_release(self.repo, core, self.commit, core_commit, "example/package", output)
        self.assertIs(caught.exception, failure)
        self.assertEqual({p.name for p in output.iterdir()}, {rp.ASSETS[0]})
        self.assertEqual(len(list(self.root.glob("swift-brave-release-*"))), 1)

    def test_constructed_archive_validation_precedes_metadata(self):
        core, core_commit, calls, runner, home = self.prepare_fixture()
        output = self.root / "invalid-container-assets"

        def invalid_builder(argv, cwd=None):
            result = runner(argv, cwd)
            if "--build-only" in argv:
                info = Path(argv[1]) / "Binary" / rp.XCFRAMEWORK_ROOT / "Info.plist"
                info.write_bytes(plistlib.dumps({"AvailableLibraries": []}))
            return result

        with patch.dict(os.environ, {"RUNNER_TEMP": str(self.root)}), \
                patch.object(rp, "run", invalid_builder):
            with self.assertRaises(rp.PackagingError):
                rp.prepare_release(self.repo, core, self.commit, core_commit, "example/package", output)
        self.assertEqual({p.name for p in output.iterdir()}, {rp.ASSETS[0]})
        self.assertEqual(len(list(self.root.glob("swift-brave-release-*"))), 1)


class IdentityAndPublicationTests(unittest.TestCase):
    def setUp(self):
        self.inputs = {"swift_brave_commit": "a" * 40, "brave_core_commit": "b" * 40,
                       "repository": "example/package", "dependency_locks": {"rust": "resolved lock"},
                       "toolchains": {"cargo": "stable today"}}

    def test_identity_binds_commits_locks_toolchains_and_payload(self):
        original = rp.release_identity(self.inputs, "c" * 64)
        for key, value in [("swift_brave_commit", "d" * 40), ("brave_core_commit", "e" * 40),
                           ("dependency_locks", {"rust": "changed"}), ("toolchains", {"cargo": "tomorrow"})]:
            self.assertNotEqual(original, rp.release_identity(dict(self.inputs, **{key: value}), "c" * 64))
        self.assertNotEqual(original, rp.release_identity(self.inputs, "d" * 64))
        self.assertEqual(original, rp.release_identity(dict(reversed(list(self.inputs.items()))), "c" * 64))

    def publication_fixture(self, parent):
        package = parent / "package"
        package.mkdir()
        (package / "Package.swift").write_bytes(manifest())
        rp.run(["git", "init", "--quiet"], package)
        rp.run(["git", "add", "Package.swift"], package)
        rp.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "publication fixture"], package)
        self.inputs["swift_brave_commit"] = rp.run(["git", "rev-parse", "HEAD"], package).decode().strip()
        assets = parent / "assets"
        assets.mkdir()
        return package, assets

    def assets(self, root, malformed=False):
        if malformed:
            (root / rp.ASSETS[0]).write_bytes(b"not a ZIP, with self-consistent metadata")
        else:
            write_archive(root / rp.ASSETS[0])
        checksum = rp.digest((root / rp.ASSETS[0]).read_bytes())
        tag, signature = rp.release_identity(self.inputs, checksum)
        url = f'https://github.com/example/package/releases/download/{tag}/{rp.ASSETS[0]}'
        (root / "Package.swift").write_bytes(rp.release_manifest(manifest(), url, checksum))
        (root / rp.ASSETS[1]).write_text(checksum + "\n")
        provenance = {"inputs": self.inputs, "release_input_signature": signature, "tag": tag,
                      "archive_sha256": checksum, "swift_package_checksum": checksum}
        (root / "provenance.json").write_bytes(rp.canonical_json(provenance))
        return tag

    def test_collision_prevents_release_and_existing_asset_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            package, root = self.publication_fixture(Path(temporary).resolve())
            self.assets(root)
            calls = []

            def occupied(argv):
                calls.append(argv)
                raise subprocess.CalledProcessError(422, argv, stderr=b"Reference already exists")

            with self.assertRaises(subprocess.CalledProcessError):
                rp.publish_release(root, "example/package", self.inputs["swift_brave_commit"], package, occupied)
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][:4], ["gh", "api", "--method", "POST"])

    def test_new_publication_validates_inputs_before_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            package, root = self.publication_fixture(Path(temporary).resolve())
            tag = self.assets(root)
            calls = []
            rp.publish_release(root, "example/package", self.inputs["swift_brave_commit"], package, calls.append)
            self.assertEqual(len(calls), 2)
            self.assertIn("ref=refs/tags/" + tag, calls[0])
            self.assertEqual(calls[1][:4], ["gh", "release", "create", tag])
            (root / rp.ASSETS[0]).write_bytes(b"tampered")
            calls.clear()
            with self.assertRaises(rp.PackagingError):
                rp.publish_release(root, "example/package", self.inputs["swift_brave_commit"], package, calls.append)
            self.assertEqual(calls, [])

    def test_publication_rejects_manifest_product_change_with_valid_binary_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            package, root = self.publication_fixture(Path(temporary).resolve())
            self.assets(root)
            manifest_path = root / "Package.swift"
            manifest_path.write_bytes(manifest_path.read_bytes().replace(b'"WebMedia"', b'"Removed"'))
            calls = []
            with self.assertRaises(rp.PackagingError):
                rp.publish_release(root, "example/package", self.inputs["swift_brave_commit"], package, calls.append)
            self.assertEqual(calls, [])

    def test_self_consistent_malformed_zip_prevents_any_remote_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            package, root = self.publication_fixture(Path(temporary).resolve())
            self.assets(root, malformed=True)
            calls = []
            with self.assertRaises(rp.PackagingError):
                rp.publish_release(root, "example/package", self.inputs["swift_brave_commit"], package, calls.append)
            self.assertEqual(calls, [])

    def test_argv_shell_characters_are_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "must-not-exist"
            value = f'$(touch {marker}); `touch {marker}` && echo unsafe'
            output = rp.run([sys.executable, "-c", "import json,sys; print(json.dumps(sys.argv[1:]))", value])
            self.assertEqual(json.loads(output), [value])
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
