#!/usr/bin/env python3
"""Isolated development payload tests; never invoke a real installer."""

import hashlib
import io
import os
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ("payload-version", "install/run.sh", "install/components/prepare.sh",
         "install/components/example.sh", "lib/logging.sh")


class PayloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="laptop-payload-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.tmpdir = self.root / "tmp"
        self.tmpdir.mkdir()
        self.stubs = self.root / "stubs"
        self.stubs.mkdir()
        gum = self.home / ".local/bin/gum"
        gum.parent.mkdir(parents=True)
        gum.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\"\n")
        gum.chmod(0o755)
        self.stub("uname", 'case "$1" in -s) echo Darwin;; -m) echo arm64;; esac')
        self.stub("sysctl", 'case "$2" in hw.optional.arm64) echo 1;; sysctl.proc_translated) echo 0;; esac')
        self.stub("curl", 'if [ "${INTERRUPT_DOWNLOAD:-0}" = 1 ]; then kill -TERM "$PPID"; exit 1; fi\n'
                          '[ "${FAIL_DOWNLOAD:-0}" = 0 ] || exit 1\n'
                          'cp "$TEST_ARCHIVE" "$3"; rc=$?\n'
                          'if [ "${RECORD_SIZE:-0}" = 1 ]; then wc -c < "$3" > "$SIZE_OUTPUT"; fi\n'
                          'exit "$rc"')
        self.stub("shasum", 'case "$3" in */.local/bin/gum) echo "74cab6235944c0e39e69edfceef81150064687dd29cacec5ec1e954637f55d0c  $3";; *) exec "$REAL_SHASUM" "$@";; esac')
        self.env = os.environ.copy()
        self.env.update(HOME=str(self.home), TMPDIR=str(self.tmpdir),
                        PATH=str(self.stubs) + os.pathsep + self.env["PATH"],
                        REAL_SHASUM=subprocess.check_output(["which", "shasum"], text=True).strip())
        self.sentinel = self.root / "outside"
        self.sentinel.write_text("unchanged")

    def stub(self, name, body):
        path = self.stubs / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def archive(self, mutation=None):
        path = self.root / "payload.tar.gz"
        with tarfile.open(path, "w:gz", format=tarfile.USTAR_FORMAT) as archive:
            for name in FILES:
                data = (ROOT / name).read_bytes()
                info = tarfile.TarInfo(name)
                info.mode = 0o644
                info.uid = info.gid = 0
                if mutation == "version" and name == "payload-version":
                    data = b"wrong\n"
                if mutation == "large" and name == "payload-version":
                    data = b"x" * 1048577
                if mutation == "expanded" and name == "payload-version":
                    data = b"x" * (20 * 1024 * 1024)
                if mutation == "component-failure" and name == "install/components/prepare.sh":
                    data = b"#!/bin/bash\nexit 7\n"
                if mutation == "mode" and name == "payload-version":
                    info.mode = 0o777
                if mutation == "owner" and name == "payload-version":
                    info.uid = 42
                if mutation in ("symlink", "hardlink", "fifo") and name == "payload-version":
                    info.type = {"symlink": tarfile.SYMTYPE, "hardlink": tarfile.LNKTYPE,
                                 "fifo": tarfile.FIFOTYPE}[mutation]
                    info.linkname = "outside" if mutation != "fifo" else ""
                    archive.addfile(info)
                    continue
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
            if mutation in ("extra", "duplicate", "traversal", "absolute"):
                name = {"extra": "extra", "duplicate": "payload-version",
                        "traversal": "../../../outside", "absolute": str(self.sentinel)}[mutation]
                info = tarfile.TarInfo(name)
                archive.addfile(info, io.BytesIO(b""))
        return path

    def execute(self, archive, digest=None, **extra):
        digest = digest or hashlib.sha256(archive.read_bytes()).hexdigest()
        source = (ROOT / "install.sh").read_text()
        source = source.replace("PAYLOAD_URL=\n", "PAYLOAD_URL=https://example.invalid/payload\n")
        source = source.replace("PAYLOAD_SHA256=\n", "PAYLOAD_SHA256=" + digest + "\n")
        bootstrap = self.root / "install.sh"
        bootstrap.write_text(source)
        env = dict(self.env, TEST_ARCHIVE=str(archive), **extra)
        result = subprocess.run(["/bin/bash", str(bootstrap), "--payload"], env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(self.sentinel.read_text(), "unchanged")
        self.assertEqual(list(self.tmpdir.iterdir()), [])
        return result

    def test_reproducible_build(self):
        a, b = self.root / "a.tar.gz", self.root / "b.tar.gz"
        for path in (a, b):
            subprocess.run(["python3", str(ROOT / "tools/build-payload.py"), str(path)], check=True)
        self.assertEqual(hashlib.sha256(a.read_bytes()).digest(), hashlib.sha256(b.read_bytes()).digest())
        with tarfile.open(a) as archive:
            self.assertEqual(archive.getnames(), list(FILES))
        result = self.execute(a)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_builder_rejects_missing_and_symlinked_inputs(self):
        source = self.root / "checkout"
        source.mkdir()
        shutil.copytree(ROOT / "tools", source / "tools")
        shutil.copytree(ROOT / "install", source / "install")
        shutil.copytree(ROOT / "lib", source / "lib")
        shutil.copy(ROOT / "payload-version", source / "payload-version")
        output = self.root / "missing.tar.gz"
        (source / "payload-version").unlink()
        result = subprocess.run(["python3", str(source / "tools/build-payload.py"), str(output)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())
        shutil.copy(ROOT / "payload-version", source / "payload-version")
        shutil.move(str(source / "install"), str(source / "actual-install"))
        (source / "install").symlink_to(source / "actual-install")
        result = subprocess.run(["python3", str(source / "tools/build-payload.py"), str(output)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_verified_payload_and_rerun(self):
        archive = self.archive()
        for _ in range(2):
            result = self.execute(archive)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("prepare complete", result.stdout)
            self.assertIn("example complete", result.stdout)
            self.assertLess(result.stdout.index("prepare complete"), result.stdout.index("example complete"))
        result = self.execute(archive, POSIXLY_CORRECT="1")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failures(self):
        archive = self.archive()
        self.assertIn("checksum mismatch", self.execute(archive, "0" * 64).stderr)
        self.assertIn("Could not download", self.execute(archive, FAIL_DOWNLOAD="1").stderr)
        interrupted = self.execute(archive, INTERRUPT_DOWNLOAD="1")
        self.assertNotEqual(interrupted.returncode, 0)
        self.env["REAL_TAR"] = shutil.which("tar")
        self.stub("tar", 'case "$1" in -xOf) exit 1;; *) exec "$REAL_TAR" "$@";; esac')
        self.assertIn("Could not extract", self.execute(archive).stderr)
        (self.stubs / "tar").unlink()
        archive.write_bytes(b"invalid archive")
        self.assertIn("Could not decompress payload archive", self.execute(archive).stderr)
        archive.write_bytes(b"x" * 5242881)
        size_output = self.root / "download-size"
        result = self.execute(archive, RECORD_SIZE="1", SIZE_OUTPUT=str(size_output))
        self.assertNotEqual(result.returncode, 0)
        normal_size = int(size_output.read_text())
        self.assertLess(normal_size, archive.stat().st_size)
        result = self.execute(archive, RECORD_SIZE="1", SIZE_OUTPUT=str(size_output), POSIXLY_CORRECT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(int(size_output.read_text()), normal_size)
        self.assertIn("Could not decompress payload archive", self.execute(self.archive("expanded")).stderr)
        for mutation in ("extra", "duplicate", "traversal", "absolute", "symlink",
                         "hardlink", "fifo", "mode", "owner", "version", "large"):
            with self.subTest(mutation=mutation):
                result = self.execute(self.archive(mutation))
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn("Running prepare", result.stdout)

    def test_unpublished_payload_fails_before_install(self):
        result = subprocess.run(["/bin/bash", str(ROOT / "install.sh"), "--payload"], env=self.env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No verified payload release", result.stderr)
        self.assertEqual(list(self.tmpdir.iterdir()), [])

    def test_runner_interface_and_stop(self):
        root = self.root / "runner"
        shutil.copytree(ROOT / "install", root / "install")
        shutil.copytree(ROOT / "lib", root / "lib")
        for name in ("prepare", "example"):
            component = root / "install/components" / (name + ".sh")
            component.write_text('#!/bin/bash\nprintf "' + name + ':%s\\n" "$1" >> "$TRACE"\n'
                                 + ('[ "${FAIL_FIRST:-0}" = 0 ] || exit 7\n' if name == "prepare" else ''))
        trace = self.root / "trace"
        env = dict(self.env, PAYLOAD_ROOT=str(root), GUM_BIN=str(self.home / ".local/bin/gum"), TRACE=str(trace))
        for mode in ("--check", "--apply"):
            subprocess.run(["/bin/bash", str(root / "install/run.sh"), mode], env=env, check=True,
                           cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(trace.read_text().splitlines(), ["prepare:--check", "example:--check",
                                                         "prepare:--apply", "example:--apply"])
        trace.write_text("")
        env["FAIL_FIRST"] = "1"
        result = subprocess.run(["/bin/bash", str(root / "install/run.sh"), "--apply"], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(trace.read_text().splitlines(), ["prepare:--apply"])
        result = self.execute(self.archive("component-failure"))
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertNotIn("Running example", result.stdout)

    def test_large_member_listing_is_bounded(self):
        archive = self.root / "many.tar.gz"
        with tarfile.open(archive, "w:gz", format=tarfile.USTAR_FORMAT) as output:
            for index in range(12000):
                output.addfile(tarfile.TarInfo("%05d" % index + "x" * 90))
        result = self.execute(archive)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not inspect payload archive", result.stderr)
        self.assertNotIn("Running prepare", result.stdout)


if __name__ == "__main__":
    unittest.main()
