#!/usr/bin/env python3
"""Build the development payload with normalized ustar and gzip metadata."""

import gzip
import io
import os
import pathlib
import re
import sys
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = (
    "payload-version",
    "install/run.sh",
    "install/components/prepare.sh",
    "install/components/example.sh",
    "lib/logging.sh",
)


def main():
    if len(sys.argv) == 2:
        version, output = "0.0.0-dev", pathlib.Path(sys.argv[1])
    elif len(sys.argv) == 4 and sys.argv[1] == "--version":
        version, output = sys.argv[2], pathlib.Path(sys.argv[3])
        if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)-rc\.(?:[1-9][0-9]*)", version):
            raise SystemExit("invalid release candidate version")
        if output.name != "laptop-payload-" + version + ".tar.gz":
            raise SystemExit("release candidate output name does not match version")
    else:
        raise SystemExit("usage: build-payload.py [--version VERSION] OUTPUT.tar.gz")
    if ROOT == output.parent.resolve() or ROOT in output.parent.resolve().parents:
        raise SystemExit("output must be outside the source repository")
    if output.exists() or output.is_symlink():
        raise SystemExit("refusing to overwrite output")
    members = []
    for name in FILES:
        path = ROOT / name
        current = ROOT
        for part in pathlib.PurePosixPath(name).parts:
            current = current / part
            if current.is_symlink():
                raise SystemExit("symlinked payload path: " + name)
        if not path.is_file():
            raise SystemExit("missing or unsafe payload file: " + name)
        members.append((name, path.read_bytes()))
    if members[0][1] != (version + "\n").encode("ascii"):
        raise SystemExit("payload version does not match source")
    fd, temporary = tempfile.mkstemp(prefix=".payload-", dir=output.parent)
    try:
        with os.fdopen(fd, "wb") as destination:
            with gzip.GzipFile(filename="", mode="wb", fileobj=destination, mtime=0) as zipped:
                with tarfile.open(fileobj=zipped, mode="w", format=tarfile.USTAR_FORMAT) as archive:
                    for name, data in members:
                        info = tarfile.TarInfo(name)
                        info.size = len(data)
                        info.mode = 0o644
                        info.uid = info.gid = info.mtime = 0
                        info.uname = info.gname = ""
                        archive.addfile(info, io.BytesIO(data))
        os.link(temporary, output)
    finally:
        os.unlink(temporary)


if __name__ == "__main__":
    main()
