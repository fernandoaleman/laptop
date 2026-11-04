#!/usr/bin/env python3
"""Verify a candidate from a Git commit without publishing artifacts."""

import argparse
import hashlib
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import tarfile
import tempfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ("payload-version", "install/run.sh", "install/components/prepare.sh",
         "install/components/example.sh", "lib/logging.sh")
INPUTS = FILES + ("install.sh", "tools/build-payload.py", "tools/verify-release.py")
VERSION = re.compile(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)-rc\.(?:[1-9][0-9]*)\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
COMMIT = re.compile(r"[0-9a-f]{40}\Z")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fail(message):
    raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, help="full reviewed Git commit SHA")
    parser.add_argument("--version", required=True)
    parser.add_argument("--payload-sha256", required=True, help="independently reviewed digest")
    parser.add_argument("--bootstrap-sha256", required=True, help="independently reviewed digest")
    parser.add_argument("--verifier-sha256", required=True, help="independently reviewed verifier digest")
    parser.add_argument("--bootstrap-file", required=True, help="reviewed candidate bootstrap")
    parser.add_argument("--local-only", action="store_true", help="check local fixtures only; never approve release")
    args = parser.parse_args()
    if not args.local_only:
        fail("release verification is unavailable; use --local-only for development checks")
    if not COMMIT.fullmatch(args.source) or not VERSION.fullmatch(args.version):
        fail("invalid source commit or release candidate version")
    if not all(SHA256.fullmatch(value) for value in (args.payload_sha256, args.bootstrap_sha256, args.verifier_sha256)):
        fail("reviewed digests must be lowercase SHA-256 values")
    running_verifier = pathlib.Path(__file__).read_bytes()
    if digest(running_verifier) != args.verifier_sha256:
        fail("running verifier differs from reviewed verifier digest")
    # Do not inherit Git overrides or dynamic-loader injection into Git.
    git_env = {key: value for key, value in os.environ.items()
               if not key.upper().startswith(("GIT_", "LD_", "DYLD_"))}
    git_env.update(GIT_NO_REPLACE_OBJECTS="1", GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    subprocess.run(["git", "cat-file", "-e", args.source + "^{commit}"], cwd=ROOT, env=git_env, check=True)
    resolved = subprocess.check_output(["git", "rev-parse", args.source + "^{commit}"], cwd=ROOT, env=git_env).decode().strip()
    if resolved != args.source:
        fail("source must be the exact commit, not a tag object")
    # Read fixed blobs directly from the commit, not from a mutable checkout.
    blobs = {}
    for name in INPUTS:
        entry = subprocess.check_output(["git", "ls-tree", args.source, "--", name], cwd=ROOT, env=git_env).decode()
        if not entry.startswith("100644 blob ") and not entry.startswith("100755 blob "):
            fail("missing or unsafe source file: " + name)
        blobs[name] = subprocess.check_output(["git", "show", args.source + ":" + name], cwd=ROOT, env=git_env)
    if blobs["tools/verify-release.py"] != running_verifier:
        fail("running verifier differs from verifier in reviewed source commit")
    if blobs["payload-version"] != (args.version + "\n").encode():
        fail("source version mismatch")
    artifact_name = "laptop-payload-" + args.version + ".tar.gz"
    builds = []
    with tempfile.TemporaryDirectory(prefix="laptop-release-verify-") as temp:
        for number in (1, 2):
            checkout = pathlib.Path(temp) / ("source-" + str(number))
            checkout.mkdir()
            for name, content in blobs.items():
                path = checkout / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            output = pathlib.Path(temp) / ("build-" + str(number)) / artifact_name
            output.parent.mkdir()
            subprocess.run([sys.executable, str(checkout / "tools/build-payload.py"),
                            "--version", args.version, str(output)], check=True)
            builds.append(output.read_bytes())
    if builds[0] != builds[1]:
        fail("independent directory builds differ")
    if len(builds[0]) > 5242880:
        fail("payload archive exceeds installer limit")
    if digest(builds[0]) != args.payload_sha256:
        fail("payload digest differs from reviewed digest")
    with tarfile.open(fileobj=io.BytesIO(builds[0]), mode="r:gz") as archive:
        members = archive.getmembers()
        if [member.name for member in members] != list(FILES):
            fail("unexpected or duplicate archive members")
        for member in members:
            if (not member.isfile() or member.uid != 0 or member.gid != 0 or member.mode != 0o644
                    or member.mtime != 0 or member.size > 1048576):
                fail("invalid archive metadata: " + member.name)
            if archive.extractfile(member).read() != blobs[member.name]:
                fail("archive member does not match source: " + member.name)
    bootstrap = blobs["install.sh"]
    url = "https://github.com/fernandoaleman/laptop/releases/download/" + args.version + "/" + artifact_name
    replacements = ((b"PAYLOAD_VERSION=0.0.0-dev\n", ("PAYLOAD_VERSION=" + args.version + "\n").encode()),
                    (b"PAYLOAD_URL=\n", ("PAYLOAD_URL=" + url + "\n").encode()),
                    (b"PAYLOAD_SHA256=\n", ("PAYLOAD_SHA256=" + args.payload_sha256 + "\n").encode()))
    for old, new in replacements:
        if bootstrap.count(old) != 1:
            fail("bootstrap is not an unbound development template")
        bootstrap = bootstrap.replace(old, new, 1)
    if digest(bootstrap) != args.bootstrap_sha256:
        fail("bootstrap digest differs from reviewed digest")
    if pathlib.Path(args.bootstrap_file).read_bytes() != bootstrap:
        fail("candidate bootstrap differs from verified source binding")
    print(json.dumps({"source_commit": args.source, "version": args.version, "payload": artifact_name,
                      "payload_sha256": args.payload_sha256, "bootstrap_sha256": args.bootstrap_sha256,
                      "verifier_sha256": args.verifier_sha256,
                      "python": sys.version.split()[0], "zlib": zlib.ZLIB_RUNTIME_VERSION,
                      "verification": "two isolated directories, same environment",
                      "release_ready": False}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, tarfile.TarError) as exc:
        raise SystemExit(str(exc))
