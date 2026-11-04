#!/usr/bin/env python3
"""Create an untrusted candidate bootstrap using a reviewed payload digest."""

import argparse
import hashlib
import os
import pathlib
import re
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--payload-sha256", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)-rc\.(?:[1-9][0-9]*)", args.version):
        raise SystemExit("invalid release candidate version")
    if not re.fullmatch(r"[0-9a-f]{64}", args.payload_sha256):
        raise SystemExit("invalid reviewed payload digest")
    output = pathlib.Path(args.output)
    if output.name != "install-" + args.version + ".sh":
        raise SystemExit("bootstrap output name does not match version")
    if ROOT == output.parent.resolve() or ROOT in output.parent.resolve().parents:
        raise SystemExit("candidate output must be outside the repository")
    bootstrap = (ROOT / "install.sh").read_bytes()
    url = "https://github.com/fernandoaleman/laptop/releases/download/" + args.version + "/laptop-payload-" + args.version + ".tar.gz"
    replacements = ((b"PAYLOAD_VERSION=0.0.0-dev\n", ("PAYLOAD_VERSION=" + args.version + "\n").encode()),
                    (b"PAYLOAD_URL=\n", ("PAYLOAD_URL=" + url + "\n").encode()),
                    (b"PAYLOAD_SHA256=\n", ("PAYLOAD_SHA256=" + args.payload_sha256 + "\n").encode()))
    for old, new in replacements:
        if bootstrap.count(old) != 1:
            raise SystemExit("bootstrap is not an unbound development template")
        bootstrap = bootstrap.replace(old, new, 1)
    fd, temporary = tempfile.mkstemp(prefix=".bootstrap-", dir=str(output.parent))
    try:
        with os.fdopen(fd, "wb") as destination:
            destination.write(bootstrap)
        os.link(temporary, output)
    finally:
        os.unlink(temporary)
    print("Candidate only; independently review bootstrap SHA-256: " + hashlib.sha256(bootstrap).hexdigest())


if __name__ == "__main__":
    main()
