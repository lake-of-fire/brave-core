"""Behavior checks for package generation; no native toolchain is invoked."""
from contextlib import ExitStack, redirect_stderr
import importlib.util
import io
from pathlib import Path
import stat
import sys
import tempfile
import tomllib
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    "make_spm_under_test", Path(__file__).resolve().parents[1] / "make_spm.py"
)
make_spm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(make_spm)

GENERATION_STEPS = (
    "clean_destination", "copy_templates", "copy_sources", "apply_patches",
    "normalize_rust_features", "configure_rust_release_profile",
)


def snapshot(root):
    return {
        file.relative_to(root).as_posix(): (stat.S_IMODE(file.stat().st_mode), file.read_bytes())
        for file in root.rglob("*") if file.is_file()
    }


class BuildModeTests(unittest.TestCase):
    def invoke(self, destination, *flags):
        with mock.patch.object(sys, "argv", ["make-spm", str(destination), *flags]):
            return make_spm.main()

    def test_build_only_preserves_existing_sources_and_skips_all_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "swift-brave"
            rust = destination / "Sources" / "BraveAdblockRust"
            rust.mkdir(parents=True)
            (destination / "Package.swift").write_text("// reviewed package\n")
            (rust / "Cargo.toml").write_text('[package]\nname = "reviewed"\n')
            executable = destination / "reviewed-script"
            executable.write_bytes(b"#!/usr/bin/env python3\n")
            executable.chmod(0o755)
            before = snapshot(destination)

            def build(stage):
                self.assertEqual(stage, destination.resolve())
                self.assertEqual(snapshot(stage), before)
                binary = stage / "Binary" / "BraveAdblockCore.xcframework"
                binary.mkdir(parents=True)
                (binary / "built").write_bytes(b"binary output")

            with ExitStack() as stack:
                generation = [stack.enter_context(mock.patch.object(
                    make_spm, name, side_effect=AssertionError("Generation must be skipped")
                )) for name in GENERATION_STEPS]
                build_mock = stack.enter_context(mock.patch.object(
                    make_spm, "build_xcframework", side_effect=build
                ))
                tests = stack.enter_context(mock.patch.object(make_spm, "run_tests"))
                self.assertEqual(self.invoke(destination, "--build-only", "--skip-tests"), 0)
                build_mock.assert_called_once_with(destination.resolve())
                tests.assert_not_called()
                for step in generation:
                    step.assert_not_called()
            after = snapshot(destination)
            self.assertEqual(set(after), set(before) | {"Binary/BraveAdblockCore.xcframework/built"})
            self.assertEqual({name: after[name] for name in before}, before)

    def test_build_only_runs_tests_unless_explicitly_skipped(self):
        self.assert_steps(("--build-only",), ("build_xcframework", "run_tests"))

    def test_default_generation_builds_and_tests_in_order(self):
        self.assert_steps((), (*GENERATION_STEPS, "build_xcframework", "run_tests"))

    def test_skip_build_retains_generation_and_test_behavior(self):
        self.assert_steps(("--skip-build",), (*GENERATION_STEPS, "run_tests"))

    def test_generation_only_skips_both_build_and_tests(self):
        self.assert_steps(("--skip-build", "--skip-tests"), GENERATION_STEPS)

    def test_conflicting_build_modes_are_rejected_before_generation(self):
        with mock.patch.object(sys, "argv", [
            "make-spm", "/nonexistent/swift-brave", "--build-only", "--skip-build"
        ]), mock.patch.object(make_spm, "ensure_swift_brave_dir") as ensure, \
                redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                make_spm.main()
            self.assertEqual(raised.exception.code, 2)
            ensure.assert_not_called()

    def assert_steps(self, flags, expected):
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            destination = Path(directory) / "swift-brave"
            destination.mkdir()
            calls = mock.Mock()
            for name in (*GENERATION_STEPS, "build_xcframework", "run_tests"):
                function = stack.enter_context(mock.patch.object(make_spm, name))
                calls.attach_mock(function, name)
            self.assertEqual(self.invoke(destination, *flags), 0)
            self.assertEqual(calls.mock_calls, [
                getattr(mock.call, name)(destination.resolve()) for name in expected
            ])


class ReleaseProfileTests(unittest.TestCase):
    EXPECTED = {
        "lto": "thin", "codegen-units": 1, "opt-level": "z",
        "panic": "abort", "strip": "symbols",
    }

    def check_profile(self, original):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "swift-brave"
            rust = destination / "Sources" / "BraveAdblockRust"
            rust.mkdir(parents=True)
            manifest = rust / "Cargo.toml"
            manifest.write_text(original)
            make_spm.configure_rust_release_profile(destination)
            first = manifest.read_bytes()
            parsed = tomllib.loads(first.decode())
            self.assertEqual(parsed["package"], {"name": "fixture"})
            self.assertEqual(parsed["profile"]["release"], self.EXPECTED)
            self.assertEqual(parsed["profile"]["dev"], {"opt-level": 0})
            make_spm.configure_rust_release_profile(destination)
            self.assertEqual(manifest.read_bytes(), first)

    def test_existing_values_with_horizontal_whitespace_are_replaced_idempotently(self):
        self.check_profile(
            '[package]\nname = "fixture"\n\n[profile.release]\n'
            '  lto = false\ncodegen-units\t= 16\nopt-level=3\n'
            'panic = "unwind"\n\tstrip = false\n'
            '\n[profile.dev]\nopt-level = 0\n'
        )

    def test_missing_settings_are_inserted_once(self):
        self.check_profile(
            '[package]\nname = "fixture"\n\n[profile.release]\n'
            'lto = "thin"\n\n[profile.dev]\nopt-level = 0\n'
        )

    def test_missing_release_profile_is_added_once(self):
        self.check_profile(
            '[package]\nname = "fixture"\n\n[profile.dev]\nopt-level = 0\n'
        )


if __name__ == "__main__":
    unittest.main()
