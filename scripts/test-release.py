#!/usr/bin/env python3
"""Exercise release automation with disposable Git repositories and a fake gh."""

import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


def command(*args, cwd, check=True, env=None):
    return subprocess.run(args, cwd=cwd, env=env, check=check, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="speaker-timer-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "work"
        self.remote = self.base / "origin.git"
        self.repo.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        self.env.pop("VERSION", None)
        for name in (".github", "SpeakerTimer", "scripts", "docs", "README.md", "CHANGELOG.md", "LICENSE", "Makefile"):
            source, target = ROOT / name, self.repo / name
            if source.is_dir():
                shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__"))
            else:
                shutil.copy2(source, target)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release-test@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "Initial fixture")
        command("git", "init", "--bare", "--initial-branch=main", str(self.remote), cwd=self.base, env=self.env)
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-u", "origin", "main")
        with (self.repo / "SpeakerTimer/Info.plist").open("rb") as source:
            self.info = plistlib.load(source)

    def git(self, *args):
        return command("git", *args, cwd=self.repo, env=self.env).stdout.strip()

    def release(self, *args):
        return command(sys.executable, "scripts/release.py", *args, cwd=self.repo, env=self.env, check=False)

    def test_first_release_tags_current_version_without_bump(self):
        result = self.release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        version = self.info["CFBundleShortVersionString"]
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", f"v{version}^{{}}"))
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertTrue(self.git("ls-remote", "origin", f"refs/tags/v{version}"))

    def test_later_release_bumps_patch_and_build(self):
        first = self.release()
        self.assertEqual(first.returncode, 0, first.stderr)
        (self.repo / "README.md").write_text((self.repo / "README.md").read_text() + "\nA tested change.\n")
        self.git("add", "README.md")
        self.git("commit", "-m", "Improve timer")
        result = self.release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        old = tuple(map(int, self.info["CFBundleShortVersionString"].split(".")))
        expected = f"{old[0]}.{old[1]}.{old[2] + 1}"
        with (self.repo / "SpeakerTimer/Info.plist").open("rb") as source:
            updated = plistlib.load(source)
        self.assertEqual(updated["CFBundleShortVersionString"], expected)
        self.assertEqual(int(updated["CFBundleVersion"]), int(self.info["CFBundleVersion"]) + 1)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", f"v{expected}^{{}}"))
        self.assertTrue((self.repo / f"docs/releases/v{expected}.md").is_file())

    def test_dirty_tree_stops_without_tag(self):
        (self.repo / "unfinished.txt").write_text("work")
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("working tree must be clean", result.stderr)
        self.assertEqual(self.git("tag", "--list"), "")

    def test_wrong_branch_and_invalid_version_stop(self):
        self.git("switch", "-c", "feature")
        self.assertIn("main branch", self.release().stderr)
        self.git("switch", "main")
        result = self.release("--version", "v2.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Use a version", result.stderr)

    def test_remote_ahead_stops_without_edits(self):
        other = self.base / "other"
        command("git", "clone", str(self.remote), str(other), cwd=self.base, env=self.env)
        command("git", "-c", "user.name=Other", "-c", "user.email=other@example.invalid",
                "commit", "--allow-empty", "-m", "Remote work", cwd=other, env=self.env)
        command("git", "push", cwd=other, env=self.env)
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Remote main has changes", result.stderr)
        self.assertEqual(self.git("status", "--porcelain"), "")


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="speaker-timer-publish-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.log = self.base / "commands.jsonl"
        fake = self.base / "gh"
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_GH_LOG"], "a") as output:
    output.write(json.dumps(args) + "\\n")
mode = os.environ["FAKE_GH_MODE"]
if args[:2] == ["release", "view"]:
    if mode in ("new", "upload-fails"):
        sys.exit(1)
    print("false" if mode == "published" else "true")
if args[:2] == ["release", "upload"] and mode == "upload-fails":
    sys.exit(1)
''')
        fake.chmod(0o755)
        with (ROOT / "SpeakerTimer/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        self.env = dict(os.environ, PATH=str(self.base) + os.pathsep + os.environ["PATH"],
                        RELEASE_TAG="v" + info["CFBundleShortVersionString"], GH_REPO="test/fixture",
                        FAKE_GH_LOG=str(self.log))

    def publish(self, mode):
        result = command("bash", "scripts/publish-release.sh", cwd=ROOT,
                         env=dict(self.env, FAKE_GH_MODE=mode), check=False)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_published_release_is_untouched(self):
        result, calls = self.publish("published")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[:2] for call in calls], [["release", "view"]])

    def test_new_release_uploads_before_publishing(self):
        result, calls = self.publish("new")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[1] for call in calls], ["view", "create", "upload", "edit"])
        self.assertIn("--draft", calls[1])
        self.assertIn("--draft=false", calls[-1])

    def test_failed_upload_leaves_draft(self):
        result, calls = self.publish("upload-fails")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call[1] for call in calls], ["view", "create", "upload"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
