import argparse
import errno
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
TEMPLATES_DIR = ROOT_DIR / "spm" / "templates" / "swift-brave"
PATCHES_DIR = ROOT_DIR / "spm" / "patches"

ALLOWED_ROOT_ENTRIES = {
    ".git",
    ".gitignore",
}

IOS_MIN_VERSION = "15.0"
MACOS_MIN_VERSION = "14.0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate the swift-brave SPM package.")
    parser.add_argument("swift_brave_path", help="Path to the swift-brave directory")
    parser.add_argument("--skip-build", action="store_true", help="Skip building the XCFramework")
    parser.add_argument("--skip-tests", action="store_true", help="Skip running swift test")
    return parser.parse_args()


def run(cmd, cwd=None, env=None):
    printable = " ".join(str(part) for part in cmd)
    print(f"# run: {printable}")
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def cargo_lock_has_package(lock_path: Path, name: str) -> bool:
    try:
        for line in lock_path.read_text().splitlines():
            if line.strip() == f'name = "{name}"':
                return True
    except FileNotFoundError:
        return False
    return False


def ensure_swift_brave_dir(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if resolved.name != "swift-brave":
        raise SystemExit(f"Destination must be a directory named 'swift-brave': {resolved}")
    if not resolved.exists() or not resolved.is_dir():
        raise SystemExit(f"Destination does not exist or is not a directory: {resolved}")
    return resolved


def is_within(root: Path, child: Path) -> bool:
    try:
        child.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def clean_destination(dest: Path):
    for entry in dest.iterdir():
        if entry.name in ALLOWED_ROOT_ENTRIES:
            continue
        if not is_within(dest, entry):
            raise SystemExit(f"Refusing to remove outside of destination: {entry}")
        if entry.is_symlink() or entry.is_file():
            entry.unlink()
        else:
            remove_tree(entry)


def remove_tree(path: Path):
    last_exc = None
    for _ in range(3):
        try:
            shutil.rmtree(path)
            return
        except OSError as exc:
            if exc.errno != errno.ENOTEMPTY:
                raise
            last_exc = exc
            time.sleep(0.05)
    if last_exc is not None:
        for root, dirs, files in os.walk(path, topdown=False):
            for name in files:
                Path(root, name).unlink()
            for name in dirs:
                Path(root, name).rmdir()
        path.rmdir()


def copy_templates(dest: Path):
    if not TEMPLATES_DIR.exists():
        raise SystemExit(f"Missing templates at {TEMPLATES_DIR}")
    for item in TEMPLATES_DIR.rglob("*"):
        relative = item.relative_to(TEMPLATES_DIR)
        target = dest / relative
        if target.name == ".gitignore" and target.exists():
            continue
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)


def copy_sources(dest: Path):
    core_include = dest / "Sources" / "BraveAdblockCore" / "include"
    core_src = dest / "Sources" / "BraveAdblockCore" / "src"
    rust_dst = dest / "Sources" / "BraveAdblockRust"

    core_include.mkdir(parents=True, exist_ok=True)
    core_src.mkdir(parents=True, exist_ok=True)

    shutil.copy2(
        ROOT_DIR / "ios" / "browser" / "api" / "brave_shields" / "adblock_engine.h",
        core_include / "AdblockEngine.h",
    )
    shutil.copy2(
        ROOT_DIR / "ios" / "browser" / "api" / "brave_shields" / "adblock_engine.mm",
        core_src / "AdblockEngine.mm",
    )

    rust_src = ROOT_DIR / "components" / "brave_shields" / "core" / "browser" / "adblock" / "rs"
    if rust_dst.exists():
        shutil.rmtree(rust_dst)
    shutil.copytree(rust_src, rust_dst)


def apply_patches(dest: Path):
    patch_files = sorted(PATCHES_DIR.glob("*.patch"))
    if not patch_files:
        raise SystemExit(f"No patches found in {PATCHES_DIR}")
    for patch in patch_files:
        run(["git", "apply", "--whitespace=nowarn", str(patch)], cwd=dest)


def normalize_rust_features(dest: Path):
    cargo_toml = dest / "Sources" / "BraveAdblockRust" / "Cargo.toml"
    if not cargo_toml.exists():
        raise SystemExit(f"Missing Cargo.toml at {cargo_toml}")
    text = cargo_toml.read_text()
    updated = text.replace(
        'single_thread_optimizations = ["adblock/unsync-regex-caching"]',
        'single_thread_optimizations = []',
    ).replace(
        'crate-type = ["rlib"]',
        'crate-type = ["rlib", "staticlib"]',
    )
    if text == updated:
        return
    cargo_toml.write_text(updated)


def configure_rust_release_profile(dest: Path):
    cargo_toml = dest / "Sources" / "BraveAdblockRust" / "Cargo.toml"
    if not cargo_toml.exists():
        raise SystemExit(f"Missing Cargo.toml at {cargo_toml}")

    text = cargo_toml.read_text()
    match = re.search(r"\[profile\.release\](.*?)(\n\[|$)", text, re.DOTALL)
    if match:
        block = match.group(0)
        content = match.group(1)
        block_end = match.end(1)
        prefix = text[: match.start(0)]
        suffix = text[block_end:]
    else:
        prefix = text.rstrip() + "\n\n[profile.release]\n"
        content = ""
        suffix = "\n"

    def ensure_setting(block_text: str, key: str, value: str) -> str:
        pattern = re.compile(rf"^{re.escape(key)}\\s*=.*$", re.MULTILINE)
        if pattern.search(block_text):
            return pattern.sub(f"{key} = {value}", block_text, count=1)
        return block_text.rstrip() + f"\n{key} = {value}\n"

    updated_content = content
    updated_content = ensure_setting(updated_content, "lto", '"thin"')
    updated_content = ensure_setting(updated_content, "codegen-units", "1")

    if match:
        updated = prefix + "[profile.release]" + updated_content + suffix
    else:
        updated = prefix + updated_content + suffix

    if updated != text:
        cargo_toml.write_text(updated)


def xcrun_sdk_path(sdk: str) -> str:
    return subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()


def xcrun_find(sdk: str, tool: str) -> str:
    return subprocess.check_output(["xcrun", "--sdk", sdk, "-f", tool], text=True).strip()


def rust_env_for_sdk(sdk: str, min_version: str) -> dict:
    sdk_path = xcrun_sdk_path(sdk)
    env = os.environ.copy()
    env["SDKROOT"] = sdk_path
    env["CC"] = xcrun_find(sdk, "clang")
    env["CXX"] = xcrun_find(sdk, "clang++")
    env["AR"] = xcrun_find(sdk, "ar")
    env["RANLIB"] = xcrun_find(sdk, "ranlib")
    if sdk.startswith("iphone"):
        env["IPHONEOS_DEPLOYMENT_TARGET"] = min_version
    else:
        env["MACOSX_DEPLOYMENT_TARGET"] = min_version
    rustflags = env.get("RUSTFLAGS", "")
    extra_flags = "-C link-arg=-dead_strip"
    env["RUSTFLAGS"] = f"{rustflags} {extra_flags}".strip()
    return env


def cargo_build(rust_dir: Path, target: str, features: str, sdk: str, min_version: str):
    env = rust_env_for_sdk(sdk, min_version)
    cmd = ["cargo", "build", "--release", "--target", target]
    if features:
        cmd.extend(["--features", features])
    run(cmd, cwd=rust_dir, env=env)


def compile_objcxx(source: Path, output: Path, sdk: str, arch: str, include_dirs: list, min_version: str):
    sdk_path = xcrun_sdk_path(sdk)
    cmd = [
        "xcrun",
        "--sdk",
        sdk,
        "clang++",
        "-c",
        str(source),
        "-o",
        str(output),
        "-std=c++17",
        "-fobjc-arc",
        "-arch",
        arch,
        "-isysroot",
        sdk_path,
    ]
    if sdk == "iphonesimulator":
        cmd.append(f"-mios-simulator-version-min={min_version}")
    elif sdk.startswith("iphone"):
        cmd.append(f"-miphoneos-version-min={min_version}")
    else:
        cmd.append(f"-mmacosx-version-min={min_version}")
    for include_dir in include_dirs:
        cmd.extend(["-I", str(include_dir)])
    run(cmd)


def compile_cpp(source: Path, output: Path, sdk: str, arch: str, include_dirs: list, min_version: str):
    sdk_path = xcrun_sdk_path(sdk)
    cmd = [
        "xcrun",
        "--sdk",
        sdk,
        "clang++",
        "-c",
        str(source),
        "-o",
        str(output),
        "-std=c++17",
        "-arch",
        arch,
        "-isysroot",
        sdk_path,
    ]
    if sdk == "iphonesimulator":
        cmd.append(f"-mios-simulator-version-min={min_version}")
    elif sdk.startswith("iphone"):
        cmd.append(f"-miphoneos-version-min={min_version}")
    else:
        cmd.append(f"-mmacosx-version-min={min_version}")
    for include_dir in include_dirs:
        cmd.extend(["-I", str(include_dir)])
    run(cmd)


def libtool_static(output: Path, objects: list):
    cmd = ["xcrun", "libtool", "-static", "-o", str(output)]
    cmd.extend(str(obj) for obj in objects)
    run(cmd)


def lipo_create(output: Path, inputs: list):
    cmd = ["xcrun", "lipo", "-create"]
    cmd.extend(str(inp) for inp in inputs)
    cmd.extend(["-output", str(output)])
    run(cmd)


def build_xcframework(dest: Path):
    rust_dir = dest / "Sources" / "BraveAdblockRust"
    core_src = dest / "Sources" / "BraveAdblockCore" / "src" / "AdblockEngine.mm"
    core_include = dest / "Sources" / "BraveAdblockCore" / "include"

    build_dir = dest / "Build"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    build_dir.mkdir()

    run(["cargo", "generate-lockfile"], cwd=rust_dir)
    lock_path = rust_dir / "Cargo.lock"
    if cargo_lock_has_package(lock_path, "rmp"):
        run(["cargo", "update", "-p", "rmp", "--precise", "0.8.8"], cwd=rust_dir)
    else:
        print("# skip: cargo package 'rmp' not found in Cargo.lock")

    rust_targets = [
        ("aarch64-apple-ios", "ios", "iphoneos", IOS_MIN_VERSION),
        ("aarch64-apple-ios-sim", "ios", "iphonesimulator", IOS_MIN_VERSION),
        ("x86_64-apple-ios", "ios", "iphonesimulator", IOS_MIN_VERSION),
        ("aarch64-apple-darwin", "ios", "macosx", MACOS_MIN_VERSION),
        ("x86_64-apple-darwin", "ios", "macosx", MACOS_MIN_VERSION),
    ]

    for target, features, sdk, min_version in rust_targets:
        cargo_build(rust_dir, target, features, sdk, min_version)

    include_dir = build_dir / "include"
    include_dir.mkdir(parents=True, exist_ok=True)
    adblock_include_dir = include_dir / "adblock"
    adblock_include_dir.mkdir(parents=True, exist_ok=True)
    generate_cxx_headers(dest, include_dir, adblock_include_dir)
    bridge_source = generate_cxx_bridge_source(dest, build_dir)

    modulemap = include_dir / "module.modulemap"
    modulemap.write_text(
        "module BraveAdblockCore {\n"
        "  header \"AdblockEngine.h\"\n"
        "  export *\n"
        "  requires objc\n"
        "}\n"
    )

    shutil.copy2(core_include / "AdblockEngine.h", include_dir / "AdblockEngine.h")

    libs_dir = build_dir / "libs"
    libs_dir.mkdir()

    def rust_lib_path(triple: str) -> Path:
        return rust_dir / "target" / triple / "release" / "libadblock_cxx.a"

    def build_for_arch(arch: str, triple: str, sdk: str, min_version: str) -> Path:
        obj_dir = libs_dir / f"obj-{sdk}-{arch}"
        obj_dir.mkdir(parents=True, exist_ok=True)
        obj_path = obj_dir / "AdblockEngine.o"
        bridge_obj = obj_dir / "adblock_cxx.o"
        compile_objcxx(
            core_src,
            obj_path,
            sdk,
            arch,
            [core_include, include_dir],
            min_version,
        )
        compile_cpp(
            bridge_source,
            bridge_obj,
            sdk,
            arch,
            [include_dir],
            min_version,
        )
        lib_path = obj_dir / "libBraveAdblockCore.a"
        libtool_static(lib_path, [obj_path, bridge_obj, rust_lib_path(triple)])
        return lib_path

    ios_arm64 = build_for_arch("arm64", "aarch64-apple-ios", "iphoneos", IOS_MIN_VERSION)
    ios_sim_arm64 = build_for_arch("arm64", "aarch64-apple-ios-sim", "iphonesimulator", IOS_MIN_VERSION)
    ios_sim_x86 = build_for_arch("x86_64", "x86_64-apple-ios", "iphonesimulator", IOS_MIN_VERSION)
    mac_arm64 = build_for_arch("arm64", "aarch64-apple-darwin", "macosx", MACOS_MIN_VERSION)
    mac_x86 = build_for_arch("x86_64", "x86_64-apple-darwin", "macosx", MACOS_MIN_VERSION)

    ios_universal = libs_dir / "ios" / "libBraveAdblockCore.a"
    ios_universal.parent.mkdir(parents=True, exist_ok=True)
    lipo_create(ios_universal, [ios_arm64])

    ios_sim_universal = libs_dir / "ios-sim" / "libBraveAdblockCore.a"
    ios_sim_universal.parent.mkdir(parents=True, exist_ok=True)
    lipo_create(ios_sim_universal, [ios_sim_arm64, ios_sim_x86])

    mac_universal = libs_dir / "macos" / "libBraveAdblockCore.a"
    mac_universal.parent.mkdir(parents=True, exist_ok=True)
    lipo_create(mac_universal, [mac_arm64, mac_x86])

    xcframework_path = dest / "Binary" / "BraveAdblockCore.xcframework"
    if xcframework_path.exists():
        shutil.rmtree(xcframework_path)
    xcframework_path.parent.mkdir(parents=True, exist_ok=True)

    run([
        "xcodebuild",
        "-create-xcframework",
        "-library",
        str(ios_universal),
        "-headers",
        str(include_dir),
        "-library",
        str(ios_sim_universal),
        "-headers",
        str(include_dir),
        "-library",
        str(mac_universal),
        "-headers",
        str(include_dir),
        "-output",
        str(xcframework_path),
    ])

    shutil.rmtree(build_dir)


def generate_cxx_headers(dest: Path, include_dir: Path, adblock_include_dir: Path):
    cxxbridge_manifest = (
        ROOT_DIR / "tools" / "crates" / "vendor" / "cxxbridge-cmd" / "Cargo.toml"
    )
    if not cxxbridge_manifest.exists():
        raise SystemExit(f"Missing cxxbridge-cmd at {cxxbridge_manifest}")

    rust_include_dir = include_dir / "rust"
    rust_include_dir.mkdir(parents=True, exist_ok=True)

    run(
        [
            "cargo",
            "run",
            "--quiet",
            "--manifest-path",
            str(cxxbridge_manifest),
            "--",
            "--header",
            "-o",
            str(rust_include_dir / "cxx.h"),
        ],
        cwd=ROOT_DIR,
    )

    run(
        [
            "cargo",
            "run",
            "--quiet",
            "--manifest-path",
            str(cxxbridge_manifest),
            "--",
            str(dest / "Sources" / "BraveAdblockRust" / "src" / "lib.rs"),
            "--header",
            "-i",
            "rust/cxx.h",
            "-o",
            str(adblock_include_dir / "lib.rs.h"),
        ],
        cwd=ROOT_DIR,
    )


def generate_cxx_bridge_source(dest: Path, build_dir: Path) -> Path:
    cxxbridge_manifest = (
        ROOT_DIR / "tools" / "crates" / "vendor" / "cxxbridge-cmd" / "Cargo.toml"
    )
    if not cxxbridge_manifest.exists():
        raise SystemExit(f"Missing cxxbridge-cmd at {cxxbridge_manifest}")

    bridge_source = build_dir / "adblock-cxx.cc"
    run(
        [
            "cargo",
            "run",
            "--quiet",
            "--manifest-path",
            str(cxxbridge_manifest),
            "--",
            str(dest / "Sources" / "BraveAdblockRust" / "src" / "lib.rs"),
            "-i",
            "rust/cxx.h",
            "-o",
            str(bridge_source),
        ],
        cwd=ROOT_DIR,
    )
    return bridge_source


def run_tests(dest: Path):
    run(["swift", "test"], cwd=dest)


def main() -> int:
    args = parse_args()
    dest = ensure_swift_brave_dir(Path(args.swift_brave_path))

    clean_destination(dest)
    copy_templates(dest)
    copy_sources(dest)
    apply_patches(dest)
    normalize_rust_features(dest)
    configure_rust_release_profile(dest)

    if not args.skip_build:
        build_xcframework(dest)

    if not args.skip_tests:
        run_tests(dest)

    print("# swift-brave generation complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
