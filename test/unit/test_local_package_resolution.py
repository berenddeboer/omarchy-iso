#!/usr/bin/python

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PREPARER = ROOT / "builder/prepare-local-repo.sh"


@unittest.skipUnless(
    all(shutil.which(tool) for tool in ("pacman", "repo-add", "bsdtar", "zstd")),
    "Arch package tools required",
)
class LocalPackageResolutionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.mirror = self.directory / "mirror"
        self.remote = self.directory / "remote"
        self.local = self.directory / "local"
        self.sync = self.directory / "db/sync"
        for directory in (self.mirror, self.remote, self.sync):
            directory.mkdir(parents=True)
        self.online_config = self.directory / "online.conf"
        self.online_config.write_text(
            "[options]\nArchitecture = auto\nSigLevel = Never\n"
            f"[remote]\nServer = file://{self.remote}\n"
        )
        self.config = self.directory / "pacman.conf"

    def package(self, directory, name, version="1-1", depends=(), provides=()):
        staging = self.directory / "staging"
        staging.mkdir(exist_ok=True)
        (staging / ".PKGINFO").write_text(
            f"pkgname = {name}\npkgver = {version}\n"
            "pkgdesc = resolver test\narch = any\nsize = 1\n"
            + "".join(f"depend = {value}\n" for value in depends)
            + "".join(f"provides = {value}\n" for value in provides)
        )
        archive = directory / f"{name}-{version}-any.pkg.tar.zst"
        subprocess.run(
            ["bsdtar", "--zstd", "-cf", str(archive), "-C", str(staging), ".PKGINFO"],
            check=True, capture_output=True,
        )
        return archive.name

    def prepare(self, *names):
        return subprocess.run(
            ["bash", str(PREPARER), str(self.mirror), str(self.local),
             str(self.online_config), str(self.config), *names],
            capture_output=True, text=True,
        )

    def resolve(self, *targets):
        subprocess.run(
            ["repo-add", str(self.remote / "remote.db.tar.gz"),
             *map(str, self.remote.glob("*.pkg.tar.zst"))],
            check=True, capture_output=True,
        )
        # Seed sync databases directly: resolver tests require no network,
        # package installation, or root privileges.
        for directory, name in ((self.remote, "remote"), (self.local, "omarchy-local")):
            shutil.copyfile(directory / f"{name}.db.tar.gz", self.sync / f"{name}.db")
        return subprocess.run(
            ["pacman", "--config", str(self.config), "--dbpath", str(self.sync.parent),
             "--noconfirm", "-S", "--print", "--print-format", "%f", *targets],
            capture_output=True, text=True,
        )

    def test_local_metadata_adds_versioned_and_transitive_dependencies(self):
        runtime = self.package(self.mirror, "runtime", depends=("theme-intros>=2", "settings-api"))
        settings = self.package(self.mirror, "settings", provides=("settings-api",))
        intros = self.package(self.remote, "theme-intros", "2-1", depends=("codec",))
        codec = self.package(self.remote, "codec")
        # A newer published runtime must not replace the local source build.
        self.package(self.remote, "runtime", "99-1", depends=("wrong-dependency",))
        prepared = self.prepare("runtime", "settings")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        resolved = self.resolve("runtime", "settings")
        self.assertEqual(resolved.returncode, 0, resolved.stderr + resolved.stdout)
        self.assertEqual(set(resolved.stdout.splitlines()), {runtime, settings, intros, codec})

        # After download/pruning, the same closure must resolve with only the
        # offline repository available, as it will during installation.
        for name in (intros, codec):
            shutil.copyfile(self.remote / name, self.mirror / name)
        stale = self.package(self.mirror, "stale")
        pruned = subprocess.run(
            ["bash", str(ROOT / "builder/prune-offline-mirror.sh"), str(self.mirror)],
            input=resolved.stdout, capture_output=True, text=True,
        )
        self.assertEqual(pruned.returncode, 0, pruned.stderr)
        self.assertFalse((self.mirror / stale).exists())
        subprocess.run(
            ["repo-add", str(self.mirror / "offline.db.tar.gz"),
             *map(str, self.mirror.glob("*.pkg.tar.zst"))],
            check=True, capture_output=True,
        )
        shutil.copyfile(self.mirror / "offline.db.tar.gz", self.sync / "offline.db")
        self.config.write_text(
            "[options]\nArchitecture = auto\nSigLevel = Never\n"
            f"[offline]\nServer = file://{self.mirror}\n"
        )
        offline = subprocess.run(
            ["pacman", "--config", str(self.config), "--dbpath", str(self.sync.parent),
             "--noconfirm", "-S", "--print", "--print-format", "%f", "runtime", "settings"],
            capture_output=True, text=True,
        )
        self.assertEqual(offline.returncode, 0, offline.stderr + offline.stdout)
        self.assertEqual(set(offline.stdout.splitlines()), {runtime, settings, intros, codec})

    def test_missing_local_dependency_is_not_silently_omitted(self):
        self.package(self.mirror, "runtime", depends=("missing-intros",))
        self.package(self.remote, "unrelated")
        prepared = self.prepare("runtime")
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        resolved = self.resolve("runtime")
        self.assertNotEqual(resolved.returncode, 0)
        self.assertIn("missing-intros", resolved.stdout + resolved.stderr)

    def test_missing_local_build_aborts(self):
        prepared = self.prepare("runtime")
        self.assertNotEqual(prepared.returncode, 0)
        self.assertIn("local build not found for runtime", prepared.stderr)

    def test_duplicate_local_builds_abort(self):
        self.package(self.mirror, "runtime")
        self.package(self.mirror, "runtime", "2-1")
        prepared = self.prepare("runtime")
        self.assertNotEqual(prepared.returncode, 0)
        self.assertIn("multiple local builds found for runtime", prepared.stderr)


if __name__ == "__main__":
    unittest.main()
