import argparse
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("make_spm", Path(__file__).resolve().parents[1] / "make_spm.py")
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)


class GeneratorModeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="swift-brave-generator-tests-")).resolve()

    @classmethod
    def tearDownClass(cls):
        trash = Path.home() / ".Trash"
        if trash.resolve() != trash.absolute():
            raise RuntimeError("Aliased Trash directory")
        trash.mkdir(exist_ok=True)
        shutil.move(str(cls.root), str(trash / cls.root.name))

    def fixture(self):
        parent = Path(tempfile.mkdtemp(dir=self.root))
        dest = parent / "swift-brave"
        dest.mkdir()
        (dest / "Package.swift").write_text("fixture manifest")
        rust = dest / "Sources" / "BraveAdblockRust"
        rust.mkdir(parents=True)
        (rust / "Cargo.toml").write_text("fixture cargo")
        return parent, dest

    def test_build_only_never_regenerates_or_patches_existing_sources(self):
        _, dest = self.fixture()
        before = {str(p.relative_to(dest)): p.read_bytes() for p in dest.rglob("*") if p.is_file()}
        args = argparse.Namespace(swift_brave_path=str(dest), build_only=True, skip_build=False, skip_tests=True)
        with patch.object(generator, "parse_args", return_value=args), \
             patch.object(generator, "clean_destination") as clean, \
             patch.object(generator, "copy_templates") as templates, \
             patch.object(generator, "copy_sources") as sources, \
             patch.object(generator, "apply_patches") as patches, \
             patch.object(generator, "normalize_rust_features") as normalize, \
             patch.object(generator, "configure_rust_release_profile") as profile, \
             patch.object(generator, "build_xcframework") as build, \
             patch.object(generator, "run_tests") as tests:
            self.assertEqual(generator.main(), 0)
        build.assert_called_once_with(dest)
        for operation in (clean, templates, sources, patches, normalize, profile, tests):
            operation.assert_not_called()
        after = {str(p.relative_to(dest)): p.read_bytes() for p in dest.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_build_only_rejects_missing_generated_rust_input(self):
        parent = Path(tempfile.mkdtemp(dir=self.root))
        dest = parent / "swift-brave"
        dest.mkdir()
        (dest / "Package.swift").write_text("fixture manifest")
        args = argparse.Namespace(swift_brave_path=str(dest), build_only=True, skip_build=False, skip_tests=True)
        with patch.object(generator, "parse_args", return_value=args), patch.object(generator, "build_xcframework") as build:
            with self.assertRaises(SystemExit):
                generator.main()
        build.assert_not_called()

    def test_conflicting_build_mode_is_rejected(self):
        with patch.object(sys, "argv", ["make-spm", "swift-brave", "--build-only", "--skip-build"]):
            with self.assertRaises(SystemExit) as error:
                generator.parse_args()
        self.assertEqual(error.exception.code, 2)

    def test_release_profile_preserves_other_keys_and_is_idempotent(self):
        _, dest = self.fixture()
        cargo = dest / "Sources/BraveAdblockRust/Cargo.toml"
        cargo.write_text('[package]\nname = "fixture"\nversion = "0.1.0"\n\n[profile.release]\nlto = false\nopt-level = 3\ndebug = true\n')
        generator.configure_rust_release_profile(dest)
        first = cargo.read_bytes()
        profile = tomllib.loads(first.decode())["profile"]["release"]
        self.assertEqual(profile, {"lto": "thin", "opt-level": "z", "debug": True,
                                   "codegen-units": 1, "panic": "abort", "strip": "symbols"})
        generator.configure_rust_release_profile(dest)
        self.assertEqual(cargo.read_bytes(), first)

    def test_failed_xcframework_replacement_retains_previous_binary_in_trash(self):
        parent, dest = self.fixture()
        header = dest / "Sources/BraveAdblockCore/include/AdblockEngine.h"
        header.parent.mkdir(parents=True)
        header.write_text("fixture header")
        previous = dest / "Binary/BraveAdblockCore.xcframework"
        previous.mkdir(parents=True)
        (previous / "prior.a").write_bytes(b"previous binary")
        home = parent / "home"
        home.mkdir()
        calls = []
        def run(argv, **kwargs):
            calls.append(argv)
            if argv[0] == "xcodebuild":
                raise RuntimeError("simulated create-xcframework failure")
        with patch.object(generator.Path, "home", return_value=home), \
             patch.object(generator, "run", side_effect=run), \
             patch.object(generator, "cargo_build"), \
             patch.object(generator, "generate_cxx_headers"), \
             patch.object(generator, "generate_cxx_bridge_source", return_value=dest / "Build/bridge.cc"), \
             patch.object(generator, "compile_objcxx"), patch.object(generator, "compile_cpp"), \
             patch.object(generator, "libtool_static"), patch.object(generator, "lipo_create"):
            with self.assertRaisesRegex(RuntimeError, "simulated create-xcframework failure"):
                generator.build_xcframework(dest)
        self.assertTrue(any(argv[0] == "xcodebuild" for argv in calls))
        self.assertFalse(previous.exists())
        retained = list((home / ".Trash").glob("*/BraveAdblockCore.xcframework/prior.a"))
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0].read_bytes(), b"previous binary")

    def test_template_copy_preserves_script_source_without_bytecode_caches(self):
        parent, dest = self.fixture()
        templates = parent / "templates"
        (templates / "Scripts/__pycache__").mkdir(parents=True)
        (templates / "Scripts/tool.py").write_text("fixture source")
        (templates / "Scripts/__pycache__/tool.cpython-314.pyc").write_bytes(b"fixture bytecode")
        with patch.object(generator, "TEMPLATES_DIR", templates):
            generator.copy_templates(dest)
        self.assertEqual((dest / "Scripts/tool.py").read_text(), "fixture source")
        self.assertFalse((dest / "Scripts/__pycache__").exists())

    def test_clean_retains_git_metadata_and_moves_previous_output_to_trash(self):
        parent, dest = self.fixture()
        (dest / ".git").write_text("fixture git metadata")
        (dest / ".gitignore").write_text("fixture ignore")
        home = parent / "home"
        home.mkdir()
        with patch.object(generator.Path, "home", return_value=home):
            generator.clean_destination(dest)
        self.assertEqual(sorted(p.name for p in dest.iterdir()), [".git", ".gitignore"])
        retired = list((home / ".Trash").iterdir())
        self.assertEqual(len(retired), 1)
        self.assertEqual((retired[0] / "Package.swift").read_text(), "fixture manifest")
        self.assertEqual((retired[0] / "Sources/BraveAdblockRust/Cargo.toml").read_text(), "fixture cargo")

    def test_clean_rejects_link_without_touching_its_target(self):
        parent, dest = self.fixture()
        external = parent / "external"
        external.write_text("keep")
        (dest / "linked").symlink_to(external)
        with self.assertRaises(SystemExit):
            generator.clean_destination(dest)
        self.assertEqual(external.read_text(), "keep")
        self.assertTrue((dest / "Package.swift").exists())


if __name__ == "__main__":
    unittest.main()
