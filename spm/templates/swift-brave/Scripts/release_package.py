#!/usr/bin/env python3
"""Strict generated-package correspondence and release asset preparation (stdlib only)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
from urllib.parse import urlsplit
import zipfile
from xml.parsers.expat import ExpatError
import zlib


class PackagingError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise PackagingError(message)


def safe_path(path):
    path = Path(os.path.abspath(path))
    require(path.resolve() == path, f"Symlink path refused: {path}")
    return path


def run(argv, cwd=None):
    """Arguments are data, never shell programs. Do not pass credentials in argv."""
    return subprocess.run([str(x) for x in argv], cwd=cwd, check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def sha40(value):
    require(re.fullmatch(r"[0-9a-fA-F]{40}", value) is not None, "Expected full SHA40 commit")
    return value.lower()


def verify_checkout(repo, expected):
    repo = safe_path(repo)
    expected = sha40(expected)
    actual = run(["git", "rev-parse", "HEAD^{commit}"], repo).decode().strip()
    require(actual == expected, f"Checkout commit mismatch: {repo}")
    # Both index and working tree, including mode changes; no PR base inference.
    require(not run(["git", "status", "--porcelain=v1", "--untracked-files=no"], repo),
            f"Tracked checkout is dirty: {repo}")
    return actual


def committed_files(repo, commit):
    files = {}
    listing = run(["git", "ls-tree", "-rz", "--full-tree", sha40(commit)], repo)
    for record in listing.split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        mode, kind, oid = metadata.split()
        path = raw_path.decode("utf-8")
        require(kind == b"blob" and mode in (b"100644", b"100755"),
                f"Unsupported tracked entry (symlink/submodule): {path}")
        require(not Path(path).is_absolute() and ".." not in Path(path).parts, "Unsafe Git path")
        files[path] = (mode.decode(), run(["git", "show", oid.decode()], repo))
    require("Package.swift" in files, "Missing committed Package.swift")
    return files


def swift_tokens(text):
    """Lex Swift punctuation/identifiers and opaque literals, omitting nested comments."""
    tokens = []
    length = len(text)

    def comment(i):
        if text.startswith("//", i):
            end = text.find("\n", i + 2)
            return length if end < 0 else end
        depth = 1
        i += 2
        while i < length and depth:
            if text.startswith("/*", i):
                depth += 1
                i += 2
            elif text.startswith("*/", i):
                depth -= 1
                i += 2
            else:
                i += 1
        require(depth == 0, "Unterminated Swift comment")
        return i

    def literal(i):
        start = i
        while i < length and text[i] == "#":
            i += 1
        hashes = i - start
        if i >= length or text[i] != '"':
            return None
        quote = '"""' if text.startswith('"""', i) else '"'
        i += len(quote)
        ending = quote + "#" * hashes
        escape = "\\" + "#" * hashes
        while i < length:
            if text.startswith(ending, i):
                return i + len(ending)
            if text.startswith(escape, i):
                i += len(escape)
                require(i < length, "Unterminated Swift escape")
                if text[i] == "(":
                    # Interpolation may contain calls, comments and quoted strings.
                    depth = 1
                    i += 1
                    while i < length and depth:
                        if text.startswith(("//", "/*"), i):
                            i = comment(i)
                            continue
                        end = literal(i) if text[i] in '#"' else None
                        if end is not None:
                            i = end
                            continue
                        if text[i] == "(":
                            depth += 1
                        elif text[i] == ")":
                            depth -= 1
                        i += 1
                    require(depth == 0, "Unterminated Swift interpolation")
                else:
                    i += 1
            else:
                i += 1
        raise PackagingError("Unterminated Swift string")

    i = 0
    while i < length:
        if text[i].isspace():
            i += 1
            continue
        if text.startswith(("//", "/*"), i):
            i = comment(i)
            continue
        end = literal(i) if text[i] in '#"' else None
        if end is not None:
            tokens.append(("string", text[i:end], i, end))
            i = end
            continue
        start = i
        if text[i].isalpha() or text[i] == "_":
            i += 1
            while i < length and (text[i].isalnum() or text[i] == "_"):
                i += 1
            tokens.append(("id", text[start:i], start, i))
        else:
            i += 1
            tokens.append(("punct", text[start:i], start, i))
    return tokens


def plain_string(tokens):
    require(len(tokens) == 1 and tokens[0][0] == "string", "Expected literal string argument")
    raw = tokens[0][1]
    require(raw.startswith('"') and not raw.startswith('"""') and "\\" not in raw,
            "Expected ordinary non-interpolated string")
    return raw[1:-1]


def validate_binary(url, checksum):
    parsed = urlsplit(url)
    require(parsed.scheme == "https" and parsed.netloc == "github.com" and
            not parsed.query and not parsed.fragment and
            re.fullmatch(r"/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases/download/"
                         r"[A-Za-z0-9_.-]+/BraveAdblockCore\.xcframework\.zip", parsed.path),
            "Expected GitHub HTTPS release URL without credentials/query/fragment")
    require(re.fullmatch(r"[0-9a-f]{64}", checksum) is not None, "Expected lowercase SHA256 checksum")


def binary_span(text):
    tokens = swift_tokens(text)
    matches = []
    for i in range(1, len(tokens) - 1):
        if tokens[i - 1][1] != "." or tokens[i][1] != "binaryTarget" or tokens[i + 1][1] != "(":
            continue
        stack = [")"]
        groups = [[]]
        j = i + 2
        while j < len(tokens) and stack:
            token = tokens[j]
            value = token[1]
            if token[0] != "string":
                if value in ("(", "[", "{"):
                    stack.append({"(": ")", "[": "]", "{": "}"}[value])
                elif value in (")", "]", "}"):
                    require(stack[-1] == value, "Unbalanced Swift binary target")
                    stack.pop()
                    if not stack:
                        break
                elif value == "," and len(stack) == 1:
                    groups.append([])
                    j += 1
                    continue
            groups[-1].append(token)
            j += 1
        require(not stack, "Unterminated Swift binary target")
        if not groups[-1]:
            groups.pop()
        args = {}
        for group in groups:
            require(len(group) >= 3 and group[0][0] == "id" and group[1][1] == ":",
                    "Expected labeled binary target arguments")
            key = group[0][1]
            require(key not in args, "Duplicate binary target argument")
            args[key] = group[2:]
        name = plain_string(args.get("name", []))
        if name != "BraveAdblockCore":
            continue
        if set(args) == {"name", "path"}:
            require(plain_string(args["path"]) == "Binary/BraveAdblockCore.xcframework",
                    "Unexpected local BraveAdblockCore path")
        else:
            require(set(args) == {"name", "url", "checksum"}, "Unexpected BraveAdblockCore shape")
            validate_binary(plain_string(args["url"]), plain_string(args["checksum"]))
        matches.append((tokens[i - 1][2], tokens[j][3]))
    require(len(matches) == 1, "Expected exactly one BraveAdblockCore binary target")
    return matches[0]


def normalize_manifest(data):
    text = data.decode("utf-8")
    start, end = binary_span(text)
    return (text[:start] + '.binaryTarget(name: "BraveAdblockCore", path: "<release-binary>")' + text[end:]).encode("utf-8")


def release_manifest(data, url, checksum):
    validate_binary(url, checksum)
    text = data.decode("utf-8")
    start, end = binary_span(text)
    replacement = ('.binaryTarget(name: "BraveAdblockCore", url: ' + json.dumps(url) +
                   ', checksum: ' + json.dumps(checksum) + ')')
    return (text[:start] + replacement + text[end:]).encode("utf-8")


RUST_LOCK = "Sources/BraveAdblockRust/Cargo.lock"
# These are build outputs, never omissions from the tracked source comparison.
BUILD_TREES = ("Binary", "Sources/BraveAdblockRust/target")


def stage_files(stage, after_build=False):
    stage = safe_path(stage)
    files = {}
    for directory, dirs, names in os.walk(stage, followlinks=False):
        for name in list(dirs):
            entry = Path(directory) / name
            relative = entry.relative_to(stage).as_posix()
            require(not entry.is_symlink(), f"Symlink in staged package: {relative}")
            if after_build and relative in BUILD_TREES:
                dirs.remove(name)
        for name in names:
            entry = Path(directory) / name
            relative = entry.relative_to(stage).as_posix()
            require(entry.is_file() and not entry.is_symlink(), f"Nonregular staged entry: {relative}")
            files[relative] = ("100755" if entry.stat().st_mode & 0o111 else "100644", entry.read_bytes())
    return files


def compare_package(repo, commit, stage, after_build=False):
    verify_checkout(repo, commit)
    expected = committed_files(repo, commit)
    require(not any(p == tree or p.startswith(tree + "/") for p in expected for tree in BUILD_TREES),
            "Tracked files must not occupy build-output trees")
    actual = stage_files(stage, after_build)
    extra = set(actual) - set(expected)
    if after_build:
        extra.discard(RUST_LOCK)  # Only an untracked, generated build input; captured in provenance.
    require(not extra and not (set(expected) - set(actual)),
            f"Package file set mismatch; extra={sorted(extra)}, missing={sorted(set(expected) - set(actual))}")
    for name, (mode, data) in expected.items():
        actual_mode, other = actual[name]
        require(mode == actual_mode, f"Package file mode mismatch: {name}")
        if name == "Package.swift":
            data, other = normalize_manifest(data), normalize_manifest(other)
        require(data == other, f"Package content mismatch: {name}")


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def release_identity(inputs, archive_sha):
    require(re.fullmatch(r"[0-9a-f]{64}", archive_sha) is not None, "Invalid archive SHA256")
    sha40(inputs["swift_brave_commit"])
    sha40(inputs["brave_core_commit"])
    signature = digest(canonical_json(inputs))
    # Full hashes bind commits, resolved locks/toolchains and payload, without truncation collisions.
    return "binary-" + signature + "-" + archive_sha, signature


def lock_inputs(core, stage):
    paths = [("package/" + RUST_LOCK, stage / RUST_LOCK)]
    cxx = core / "tools/crates/vendor/cxxbridge-cmd"
    # Retain available locks along the CXX manifest's workspace ancestry; no registry snapshot claim.
    paths += [("brave-core/" + (parent / "Cargo.lock").relative_to(core).as_posix(), parent / "Cargo.lock")
              for parent in [cxx, cxx.parent, cxx.parent.parent, core / "tools", core]]
    result = {}
    for name, path in paths:
        if path.exists():
            safe_path(path)
            require(path.is_file(), f"Lock must be a regular file: {path}")
            data = path.read_bytes()
            result[name] = {"sha256": digest(data), "content": data.decode("utf-8")}
    require("package/" + RUST_LOCK in result, "Build did not produce Rust Cargo.lock")
    require(any(key.startswith("brave-core/") for key in result), "No CXX Cargo lock available")
    return result


def write_new(path, data):
    path = safe_path(path)
    with path.open("xb") as output:
        output.write(data)


XCFRAMEWORK_ROOT = "BraveAdblockCore.xcframework"


def archive_relative_path(value):
    require(isinstance(value, str) and bool(value) and
            not any(char in value for char in ("\\", "\0", ":")) and
            all(part not in ("", ".", "..") for part in value.split("/")),
            "Unsafe XCFramework relative path")
    return value


def validate_xcframework_archive(path):
    """Check the container and declarations without extraction; no native ABI claim."""
    path = safe_path(path)
    try:
        with zipfile.ZipFile(path) as archive:
            entries = {}
            directories = set()
            for member in archive.infolist():
                name = member.orig_filename
                require("\0" not in name, "NUL in XCFramework member name")
                is_dir = member.is_dir()
                key = archive_relative_path(name[:-1] if is_dir else name)
                require(key == XCFRAMEWORK_ROOT or key.startswith(XCFRAMEWORK_ROOT + "/"),
                        "Unexpected XCFramework archive root")
                require(key not in entries, "Duplicate XCFramework member")
                mode = member.external_attr >> 16
                kind = stat.S_IFMT(mode)
                require(kind in (0, stat.S_IFDIR if is_dir else stat.S_IFREG) and
                        (not member.external_attr & 0x10 or is_dir),
                        "Nonregular XCFramework ZIP member")
                require(is_dir or key != XCFRAMEWORK_ROOT, "XCFramework root must be a directory")
                require(not is_dir or member.file_size == 0, "Nonempty ZIP directory")
                entries[key] = member
                if is_dir:
                    directories.add(key)
                # Reading every member to EOF checks local headers, truncation and CRCs.
                with archive.open(member) as source:
                    while source.read(1024 * 1024):
                        pass
            for key in entries:
                parts = key.split("/")
                for end in range(1, len(parts)):
                    parent = "/".join(parts[:end])
                    require(parent not in entries or parent in directories,
                            "File used as XCFramework directory")
            info_name = XCFRAMEWORK_ROOT + "/Info.plist"
            require(info_name in entries and info_name not in directories,
                    "Missing root XCFramework Info.plist")
            try:
                info = plistlib.loads(archive.read(entries[info_name]))
            except (ValueError, TypeError, OverflowError, ExpatError,
                    plistlib.InvalidFileException) as error:
                raise PackagingError("Invalid XCFramework Info.plist") from error
            require(isinstance(info, dict), "XCFramework Info.plist must be a dictionary")
            libraries = info.get("AvailableLibraries")
            require(isinstance(libraries, list) and bool(libraries), "Missing AvailableLibraries")
            identifiers = set()
            for library in libraries:
                require(isinstance(library, dict), "Invalid AvailableLibraries entry")
                identifier = archive_relative_path(library.get("LibraryIdentifier"))
                require("/" not in identifier and identifier not in identifiers,
                        "Unsafe or duplicate LibraryIdentifier")
                identifiers.add(identifier)
                base = XCFRAMEWORK_ROOT + "/" + identifier + "/"
                library_name = base + archive_relative_path(library.get("LibraryPath"))
                require(library_name in entries and library_name not in directories and
                        entries[library_name].file_size > 0, "Missing or empty declared library")
                if "HeadersPath" in library:
                    headers = base + archive_relative_path(library["HeadersPath"]) + "/"
                    require(any(name.startswith(headers) and name not in directories and
                                member.file_size > 0 for name, member in entries.items()),
                            "Missing or empty declared headers")
    except (OSError, zipfile.BadZipFile, zipfile.LargeZipFile, RuntimeError,
            NotImplementedError, EOFError, zlib.error) as error:
        raise PackagingError("Cannot read valid XCFramework ZIP") from error


def raise_walk_error(error):
    raise error


def prepare_release(package, core, swift_commit, brave_commit, repository, output):
    package, core, output = map(safe_path, (package, core, output))
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository), "Invalid repository")
    swift_commit = verify_checkout(package, swift_commit)
    brave_commit = verify_checkout(core, brave_commit)
    runner_temp = safe_path(os.environ["RUNNER_TEMP"])
    for source in (package, core):
        require(runner_temp != source and source not in runner_temp.parents,
                "RUNNER_TEMP must be outside source checkouts")
        require(output != source and source not in output.parents,
                "Asset directory must be outside source checkouts")
    require(runner_temp in output.parents, "Assets must be under RUNNER_TEMP")
    require(not output.exists(), "Asset directory must be fresh")
    output.mkdir()
    # Stage remains outside the source checkout; no initial deletion or cache duplication.
    work = Path(tempfile.mkdtemp(prefix="swift-brave-release-", dir=runner_temp))
    stage = work / "swift-brave"
    stage.mkdir()
    commands = []

    def execute(argv, cwd=None):
        commands.append({"argv": [str(x) for x in argv], "cwd": str(cwd) if cwd else None})
        try:
            return run(argv, cwd)
        except subprocess.CalledProcessError as error:
            write_new(work / "command-failure.json", canonical_json({
                "argv": commands[-1]["argv"], "returncode": error.returncode,
                "stdout": (error.stdout or b"").decode("utf-8", errors="replace"),
                "stderr": (error.stderr or b"").decode("utf-8", errors="replace"),
            }))
            raise

    succeeded = False
    try:
        execute([core / "make-spm", stage, "--skip-build", "--skip-tests"], core)
        compare_package(package, swift_commit, stage)
        verify_checkout(core, brave_commit)
        toolchains = {}
        for argv in [["rustc", "--version", "--verbose"], ["cargo", "--version"],
                     ["swift", "--version"], ["xcodebuild", "-version"],
                     ["xcrun", "clang++", "--version"]]:
            toolchains[" ".join(argv)] = execute(argv).decode("utf-8")
        # Parent-owned generator contract: build this stage, without regeneration or tests.
        execute([core / "make-spm", stage, "--build-only", "--skip-tests"], core)
        compare_package(package, swift_commit, stage, after_build=True)
        # No tracked Brave source changes allowed, including CXX workspace locks.
        verify_checkout(core, brave_commit)
        locks = lock_inputs(core, stage)
        inputs = {"swift_brave_commit": swift_commit, "brave_core_commit": brave_commit,
                  "repository": repository, "dependency_locks": locks, "toolchains": toolchains}
        binary = safe_path(stage / "Binary/BraveAdblockCore.xcframework")
        require(binary.is_dir(), "Missing built XCFramework")
        archive = safe_path(output / "BraveAdblockCore.xcframework.zip")
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as zipped:
            for directory, dirs, names in os.walk(binary, followlinks=False, onerror=raise_walk_error):
                require(stat.S_ISDIR(Path(directory).lstat().st_mode), "Non-directory XCFramework tree")
                dirs.sort()
                for name in dirs:
                    require(stat.S_ISDIR((Path(directory) / name).lstat().st_mode),
                            "Symlink or non-directory in XCFramework")
                for name in sorted(names):
                    path = safe_path(Path(directory) / name)
                    before = path.lstat()
                    require(stat.S_ISREG(before.st_mode), "Nonregular XCFramework file")
                    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as source:
                        opened = os.fstat(source.fileno())
                        require(stat.S_ISREG(opened.st_mode) and
                                (before.st_dev, before.st_ino) == (opened.st_dev, opened.st_ino),
                                "XCFramework file changed before reading")
                        member = zipfile.ZipInfo(path.relative_to(binary.parent).as_posix())
                        member.create_system = 3
                        member.external_attr = opened.st_mode << 16
                        member.compress_type = zipfile.ZIP_DEFLATED
                        with zipped.open(member, "w") as target:
                            shutil.copyfileobj(source, target)
                        after = os.fstat(source.fileno())
                        require((opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) ==
                                (after.st_size, after.st_mtime_ns, after.st_ctime_ns),
                                "XCFramework file changed while reading")
        validate_xcframework_archive(archive)
        checksum = digest(archive.read_bytes())
        tag, signature = release_identity(inputs, checksum)
        url = f"https://github.com/{repository}/releases/download/{tag}/{archive.name}"
        manifest = committed_files(package, swift_commit)["Package.swift"][1]
        write_new(output / "Package.swift", release_manifest(manifest, url, checksum))
        write_new(output / "BraveAdblockCore.xcframework.checksum", (checksum + "\n").encode())
        provenance = {"schema": 1, "inputs": inputs, "release_input_signature": signature,
                      "tag": tag, "archive_sha256": checksum, "swift_package_checksum": checksum,
                      "commands": commands,
                      "qualification": "Source correspondence only; native/distribution checks remain separate.",
                      "resolution": "Rust registry/toolchain resolution is not hermetic or reproducible."}
        write_new(output / "provenance.json", canonical_json(provenance) + b"\n")
        succeeded = True
    finally:
        if succeeded:
            trash = safe_path(Path.home() / ".Trash")
            trash.mkdir(exist_ok=True)
            work.rename(trash / work.name)
        else:
            print(f"Release preparation failed; stage retained: {work}; failed output retained: {output}")


ASSETS = ("BraveAdblockCore.xcframework.zip", "BraveAdblockCore.xcframework.checksum",
          "Package.swift", "provenance.json")


def publish_release(assets, repository, swift_commit, package, runner=run):
    """Create tag atomically, then a new release; never update an existing tag/asset."""
    assets = safe_path(assets)
    swift_commit = verify_checkout(package, swift_commit)
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository), "Invalid repository")
    require({p.name for p in assets.iterdir()} == set(ASSETS), "Unexpected release asset set")
    for name in ASSETS:
        require(safe_path(assets / name).is_file(), "Nonregular release asset")
    provenance = json.loads((assets / "provenance.json").read_text())
    inputs = provenance["inputs"]
    require(inputs["swift_brave_commit"] == swift_commit and inputs["repository"] == repository,
            "Release provenance source mismatch")
    checksum = digest((assets / ASSETS[0]).read_bytes())
    tag, signature = release_identity(inputs, checksum)
    require(provenance["tag"] == tag and provenance["release_input_signature"] == signature and
            provenance["archive_sha256"] == checksum and provenance["swift_package_checksum"] == checksum,
            "Release provenance payload mismatch")
    require((assets / ASSETS[1]).read_text() == checksum + "\n", "Checksum asset mismatch")
    url = f"https://github.com/{repository}/releases/download/{tag}/{ASSETS[0]}"
    manifest = (assets / "Package.swift").read_bytes()
    approved_manifest = committed_files(package, swift_commit)["Package.swift"][1]
    require(release_manifest(approved_manifest, url, checksum) == manifest,
            "Release manifest differs from the committed package")
    validate_xcframework_archive(assets / ASSETS[0])
    # POST refs fails on any collision, including an earlier interrupted publication.
    # No existence-probe error can accidentally authorize overwriting an existing release.
    runner(["gh", "api", "--method", "POST", f"repos/{repository}/git/refs",
            "-f", f"ref=refs/tags/{tag}", "-f", f"sha={swift_commit}"])
    runner(["gh", "release", "create", tag, "--repo", repository, "--verify-tag",
            "--target", swift_commit, "--title", tag, "--latest=false", "--notes",
            "Exact input commits, resolved locks/toolchains and payload checksum are in provenance.json. "
            "Package.swift is a proposal for coordinator review; no branch was modified.",
            *[str(assets / name) for name in ASSETS]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    verify = sub.add_parser("verify-checkout")
    verify.add_argument("--repo", required=True)
    verify.add_argument("--commit", required=True)
    compare = sub.add_parser("compare")
    compare.add_argument("--package", required=True)
    compare.add_argument("--swift-commit", required=True)
    compare.add_argument("--stage", required=True)
    compare.add_argument("--after-build", action="store_true")
    prepare = sub.add_parser("prepare")
    for flag in ("package", "core", "swift-commit", "brave-commit", "repository", "output"):
        prepare.add_argument("--" + flag, required=True)
    publish = sub.add_parser("publish")
    for flag in ("assets", "repository", "swift-commit", "package"):
        publish.add_argument("--" + flag, required=True)
    args = vars(parser.parse_args())
    command = args.pop("command")
    if command == "verify-checkout":
        verify_checkout(args["repo"], args["commit"])
    elif command == "compare":
        compare_package(args["package"], args["swift_commit"], args["stage"], args["after_build"])
    elif command == "prepare":
        prepare_release(**args)
    else:
        publish_release(**args)


if __name__ == "__main__":
    main()
