#!/usr/bin/env python3
"""Prepare and atomically push a release; GitHub Actions builds and publishes it."""

import argparse
from datetime import date
import html
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def run(*args, check=True):
    return subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check)


def git(*args):
    return run("git", *args).stdout.strip()


def version_tuple(value):
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", value):
        raise ValueError("Use a version like 1.2.3 without a v prefix.")
    return tuple(map(int, value.split(".")))


def generated_notes(version, changes):
    return f"""# Speaker Timer {version}

Speaker Timer keeps your presentation timeline visible above full-screen slides without taking focus.

## Changes

{changes}

## Install

Download **Speaker-Timer-{version}-universal.dmg**, open it, and drag Speaker Timer into Applications. The ZIP contains the same universal app for Apple Silicon and Intel Macs.

- Requires macOS 14 Sonoma or later.
- Ad-hoc signed and not Apple-notarized. If blocked, use System Settings → Privacy & Security → Open Anyway for an app you trust.
- SHA-256 checksums are in `SHA256SUMS`.
- Verify provenance with `gh attestation verify Speaker-Timer-{version}-universal.dmg --repo laixintao/speaker-timer`.
"""


def main(requested=None):
    if git("status", "--porcelain"):
        raise ValueError("Commit or stash your changes before releasing; the working tree must be clean.")
    if git("branch", "--show-current") != "main":
        raise ValueError("Release from the main branch.")
    if not git("remote"):
        raise ValueError("Configure the origin remote before releasing.")

    remote_main = git("ls-remote", "origin", "refs/heads/main")
    if remote_main:
        git("fetch", "--quiet", "origin", "refs/heads/main", "--tags")
        remote_head = git("rev-parse", "FETCH_HEAD")
        if run("git", "merge-base", "--is-ancestor", remote_head, "HEAD", check=False).returncode:
            raise ValueError("Remote main has changes you do not have. Pull or rebase before releasing.")
    else:
        git("fetch", "--quiet", "origin", "--tags")

    info_path = ROOT / "SpeakerTimer/Info.plist"
    info_text = info_path.read_text()
    info = plistlib.loads(info_text.encode())
    current = info["CFBundleShortVersionString"]
    current_tuple = version_tuple(current)
    version_tags = [tag for tag in git("tag", "--list", "v*", "--sort=-version:refname").splitlines()
                    if re.fullmatch(r"v\d+\.\d+\.\d+", tag)]
    first_release = not version_tags
    if first_release:
        version = requested or current
        if version_tuple(version) < current_tuple:
            raise ValueError(f"The first release cannot be older than {current}.")
    else:
        major, minor, patch = current_tuple
        version = requested or f"{major}.{minor}.{patch + 1}"
        if version_tuple(version) <= current_tuple:
            raise ValueError(f"The next version must be newer than {current}.")
    tag = f"v{version}"

    if run("git", "show-ref", "--verify", "--quiet", f"refs/tags/{tag}", check=False).returncode == 0:
        raise ValueError(f"{tag} already exists locally. Retry its push instead of releasing again.")
    if git("ls-remote", "origin", f"refs/tags/{tag}"):
        raise ValueError(f"{tag} already exists on origin. Choose a new version.")

    base = version_tags[0] if version_tags else None
    revision = f"{base}..HEAD" if base else "HEAD"
    commits = git("log", "--no-merges", "--format=%h%x09%s", revision)
    changes = []
    for line in commits.splitlines():
        sha, subject = line.split("\t", 1)
        subject = re.sub(r"([\\`*_\[\]])", r"\\\1", html.escape(subject))
        changes.append(f"- {subject} (`{sha}`)")
    if not changes:
        raise ValueError("There are no new commits since the previous release.")
    change_text = "\n".join(changes)

    if version != current:
        build = int(info["CFBundleVersion"]) + 1
        for key, value in (("CFBundleShortVersionString", version), ("CFBundleVersion", str(build))):
            info_text, count = re.subn(
                rf"(<key>{key}</key>\s*<string>)[^<]*(</string>)",
                lambda match: match[1] + value + match[2], info_text
            )
            if count != 1:
                raise ValueError(f"Expected one {key} string in Info.plist.")
        info_path.write_text(info_text)

    notes_path = ROOT / f"docs/releases/{tag}.md"
    if not notes_path.exists():
        notes_path.write_text(generated_notes(version, change_text))
    changelog_path = ROOT / "CHANGELOG.md"
    changelog = changelog_path.read_text()
    if not re.search(rf"^## {re.escape(version)}(?:\s|$)", changelog, re.MULTILINE):
        heading, separator, remainder = changelog.partition("\n")
        entry = f"\n## {version} — {date.today().isoformat()}\n\n{change_text}\n\n[Release notes](docs/releases/{tag}.md)\n"
        changelog_path.write_text(heading + separator + entry + remainder)

    subprocess.run([sys.executable, "scripts/check-project.py", "--release-tag", tag], cwd=ROOT, check=True)
    paths = ["SpeakerTimer/Info.plist", "CHANGELOG.md", f"docs/releases/{tag}.md"]
    changed = git("status", "--porcelain", "--", *paths)
    if changed:
        git("add", "--", *paths)
        git("commit", "-m", f"Release {tag}")
    git("tag", "-a", tag, "-m", f"Speaker Timer {version}")

    pushed = run("git", "push", "--atomic", "origin", "HEAD:refs/heads/main", f"refs/tags/{tag}", check=False)
    if pushed.returncode:
        print(pushed.stderr, file=sys.stderr)
        print(f"Commit and tag are kept locally. Retry with:\n"
              f"  git push --atomic origin HEAD:refs/heads/main refs/tags/{tag}\n"
              "Do not run make release again for this version.", file=sys.stderr)
        return 1
    print(f"Pushed {tag}. GitHub Actions will test, package, attest, and publish.\n"
          "Workflow: https://github.com/laixintao/speaker-timer/actions/workflows/release.yml\n"
          f"Release: https://github.com/laixintao/speaker-timer/releases/tag/{tag}")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=os.environ.get("VERSION") or None)
    try:
        sys.exit(main(parser.parse_args().version))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
