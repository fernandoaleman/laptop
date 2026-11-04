#!/usr/bin/env python3
"""Build the development payload with normalized ustar and gzip metadata."""

import gzip
import io
import os
import pathlib
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
    if len(sys.argv) != 2:
        raise SystemExit("usage: build-payload.py OUTPUT.tar.gz")
    output = pathlib.Path(sys.argv[1])
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
    if members[0][1] != b"0.0.0-dev\n":
        raise SystemExit("unexpected development payload version")
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
