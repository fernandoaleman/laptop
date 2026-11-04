#!/usr/bin/env python3
"""Isolated development payload tests; never invoke a real installer."""

import hashlib
import io
import os
import pathlib
import random
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

    def test_candidate_version_and_name_binding(self):
        source = self.root / "candidate"
        source.mkdir()
        shutil.copytree(ROOT / "tools", source / "tools")
        shutil.copytree(ROOT / "install", source / "install")
        shutil.copytree(ROOT / "lib", source / "lib")
        (source / "payload-version").write_text("v2.0.0-rc.1\n")
        builder = source / "tools/build-payload.py"
        output = self.root / "laptop-payload-v2.0.0-rc.1.tar.gz"
        def build(version, target):
            return subprocess.run(["python3", str(builder), "--version", version, str(target)],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(build("v2.0.0-rc.2", output).returncode, 0)
        self.assertNotEqual(build("latest", output).returncode, 0)
        self.assertNotEqual(build("v2.0.0-rc.1", self.root / "wrong.tar.gz").returncode, 0)
        self.assertFalse(output.exists())
        self.assertEqual(build("v2.0.0-rc.1", output).returncode, 0)
        self.assertNotEqual(build("v2.0.0-rc.1", output).returncode, 0)
        with tarfile.open(output) as archive:
            self.assertEqual(archive.extractfile("payload-version").read(), b"v2.0.0-rc.1\n")

    def test_release_verifier_with_reviewed_fixture(self):
        source = self.root / "reviewed-source"
        source.mkdir()
        shutil.copytree(ROOT / "tools", source / "tools")
        shutil.copytree(ROOT / "install", source / "install")
        shutil.copytree(ROOT / "lib", source / "lib")
        shutil.copy(ROOT / "install.sh", source / "install.sh")
        (source / "payload-version").write_text("v2.0.0-rc.1\n")
        artifact = self.root / "laptop-payload-v2.0.0-rc.1.tar.gz"
        subprocess.run(["python3", str(source / "tools/build-payload.py"), "--version",
                        "v2.0.0-rc.1", str(artifact)], check=True)
        payload_hash = hashlib.sha256(artifact.read_bytes()).hexdigest()
        template = (source / "install.sh").read_text()
        candidate_path = self.root / "install-v2.0.0-rc.1.sh"
        subprocess.run(["python3", str(ROOT / "tools/prepare-bootstrap.py"), "--version", "v2.0.0-rc.1",
                        "--payload-sha256", payload_hash, "--output", str(candidate_path)],
                       check=True, stdout=subprocess.PIPE)
        candidate = candidate_path.read_text()
        bootstrap_hash = hashlib.sha256(candidate_path.read_bytes()).hexdigest()
        self.stub("git", 'case "$1" in\n'
                         'cat-file) exit 0;;\n'
                         'rev-parse) printf "%s\\n" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;;\n'
                         'ls-tree) printf "100644 blob fake\\t%s\\n" "$4";;\n'
                         'show) cat "$FAKE_SOURCE/${2#*:}";;\n'
                         '*) exit 1;; esac')
        env = dict(self.env, FAKE_SOURCE=str(source))
        args = ["python3", str(ROOT / "tools/verify-release.py"), "--source", "a" * 40,
                "--version", "v2.0.0-rc.1", "--payload-sha256", payload_hash,
                "--bootstrap-sha256", bootstrap_hash, "--bootstrap-file", str(candidate_path),
                "--verifier-sha256", hashlib.sha256((ROOT / "tools/verify-release.py").read_bytes()).hexdigest(), "--local-only"]
        def verify(command):
            return subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result = verify(args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('"verification": "two isolated directories, same environment"', result.stdout)
        self.assertIn('"release_ready": false', result.stdout)
        self.assertNotEqual(verify(args[:-1]).returncode, 0)
        for flag in ("--payload-sha256", "--bootstrap-sha256", "--verifier-sha256"):
            bad = args.copy()
            bad[bad.index(flag) + 1] = "0" * 64
            self.assertNotEqual(verify(bad).returncode, 0)
        candidate_path.write_text("substituted\n")
        self.assertNotEqual(verify(args).returncode, 0)
        candidate_path.write_text(candidate)
        component = source / "install/components/example.sh"
        original = component.read_bytes()
        component.write_bytes(b"x" * 1048577)
        large_dir = self.root / "large-candidate"
        large_dir.mkdir()
        large_artifact = large_dir / artifact.name
        subprocess.run(["python3", str(source / "tools/build-payload.py"), "--version",
                        "v2.0.0-rc.1", str(large_artifact)], check=True)
        large_args = args.copy()
        large_args[large_args.index("--payload-sha256") + 1] = hashlib.sha256(large_artifact.read_bytes()).hexdigest()
        self.assertIn("invalid archive metadata", verify(large_args).stderr)
        component.write_bytes(random.Random(0).randbytes(6 * 1048576))
        compressed_dir = self.root / "large-compressed"
        compressed_dir.mkdir()
        compressed_artifact = compressed_dir / artifact.name
        subprocess.run(["python3", str(source / "tools/build-payload.py"), "--version",
                        "v2.0.0-rc.1", str(compressed_artifact)], check=True)
        large_args[large_args.index("--payload-sha256") + 1] = hashlib.sha256(compressed_artifact.read_bytes()).hexdigest()
        self.assertIn("payload archive exceeds installer limit", verify(large_args).stderr)
        component.write_bytes(original)
        (source / "payload-version").write_text("v2.0.0-rc.2\n")
        self.assertNotEqual(verify(args).returncode, 0)
        (source / "payload-version").write_text("v2.0.0-rc.1\n")
        (source / "install.sh").write_text(template + "PAYLOAD_URL=\n")
        self.assertNotEqual(verify(args).returncode, 0)

    def test_prepare_bootstrap_candidate_is_exclusive(self):
        output = self.root / "install-v2.0.0-rc.1.sh"
        command = ["python3", str(ROOT / "tools/prepare-bootstrap.py"),
                   "--version", "v2.0.0-rc.1", "--payload-sha256", "a" * 64,
                   "--output", str(output)]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr)
        candidate = output.read_text()
        self.assertIn("PAYLOAD_SHA256=" + "a" * 64, candidate)
        self.assertIn("/v2.0.0-rc.1/laptop-payload-v2.0.0-rc.1.tar.gz", candidate)
        self.assertNotEqual(subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode, 0)
        self.assertEqual(output.read_text(), candidate)
        self.assertEqual(list(self.root.glob(".bootstrap-*")), [])
        command[command.index("--payload-sha256") + 1] = "bad"
        self.assertNotEqual(subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode, 0)
        self.assertIn("PAYLOAD_SHA256=\n", (ROOT / "install.sh").read_text())

    def test_release_verifier_real_git_success_and_identity(self):
        source = self.root / "git-source"
        source.mkdir()
        for name in ("tools", "install", "lib"):
            shutil.copytree(ROOT / name, source / name)
        shutil.copy(ROOT / "install.sh", source / "install.sh")
        (source / "payload-version").write_text("v2.0.0-rc.1\n")
        env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=source, env=env, stderr=subprocess.PIPE).decode().strip()
        git("init", "--quiet", "--template=")
        git("add", "--", "tools", "install", "lib", "install.sh", "payload-version")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false",
            "commit", "--quiet", "-m", "fixture")
        commit = git("rev-parse", "HEAD")
        artifact = self.root / "laptop-payload-v2.0.0-rc.1.tar.gz"
        subprocess.run(["python3", str(source / "tools/build-payload.py"), "--version", "v2.0.0-rc.1", str(artifact)], check=True)
        payload_hash = hashlib.sha256(artifact.read_bytes()).hexdigest()
        candidate = self.root / "install-v2.0.0-rc.1.sh"
        subprocess.run(["python3", str(source / "tools/prepare-bootstrap.py"), "--version", "v2.0.0-rc.1",
                        "--payload-sha256", payload_hash, "--output", str(candidate)], check=True, stdout=subprocess.PIPE)
        verifier = source / "tools/verify-release.py"
        verifier_hash = hashlib.sha256(verifier.read_bytes()).hexdigest()
        args = ["python3", str(verifier), "--source", commit, "--version", "v2.0.0-rc.1",
                "--payload-sha256", payload_hash, "--bootstrap-sha256", hashlib.sha256(candidate.read_bytes()).hexdigest(),
                "--bootstrap-file", str(candidate), "--verifier-sha256", verifier_hash, "--local-only"]
        (source / "payload-version").write_text("uncommitted change\n")
        (source / "install/components/example.sh").write_text("uncommitted change\n")
        def verify(command):
            return subprocess.run(command, cwd=source, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result = verify(args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(commit, result.stdout)
        self.assertIn(payload_hash, result.stdout)
        bad = args.copy()
        bad[bad.index("--version") + 1] = "v2.0.0-rc.2"
        self.assertIn("source version mismatch", verify(bad).stderr)
        bad = args.copy()
        bad[bad.index("--source") + 1] = "0" * 40
        self.assertNotEqual(verify(bad).returncode, 0)
        bad = args.copy()
        bad[bad.index("--verifier-sha256") + 1] = "0" * 64
        self.assertNotEqual(verify(bad).returncode, 0)
        bad = args.copy()
        index = bad.index("--verifier-sha256")
        del bad[index:index + 2]
        self.assertNotEqual(verify(bad).returncode, 0)
        original_verifier = verifier.read_text()
        verifier.write_text(original_verifier + "\n# modified\n")
        self.assertIn("running verifier differs", verify(args).stderr)
        git("add", "--", "tools/verify-release.py")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false",
            "commit", "--quiet", "-m", "substituted verifier")
        other_commit = git("rev-parse", "HEAD")
        verifier.write_text(original_verifier)
        bad = args.copy()
        bad[bad.index("--source") + 1] = other_commit
        self.assertIn("verifier in reviewed source commit", verify(bad).stderr)

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
