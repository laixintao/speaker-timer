#!/usr/bin/env python3
"""Validate release metadata, resources, documentation, and local links."""

import argparse
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
VERSION = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)")


def check(tag=None):
    errors = []
    info_path = ROOT / "SpeakerTimer/Info.plist"
    with info_path.open("rb") as source:
        info = plistlib.load(source)
    version = info.get("CFBundleShortVersionString", "")
    if not VERSION.fullmatch(version):
        errors.append(f"Invalid app version: {version!r}")
    if tag is not None and tag != f"v{version}":
        errors.append(f"Release tag {tag!r} must match Info.plist: v{version}")
    if info.get("CFBundleIdentifier") != "io.xbin.speaker-timer":
        errors.append("Unexpected CFBundleIdentifier")
    if info.get("LSMinimumSystemVersion") != "14.0":
        errors.append("LSMinimumSystemVersion must be 14.0")
    if info.get("LSUIElement"):
        errors.append("Speaker Timer must remain a normal Dock application")

    required = [
        "README.md", "LICENSE", "CHANGELOG.md", "Makefile",
        "SpeakerTimer/Resources/SpeakerTimer.icns",
        "SpeakerTimer/Resources/en.lproj/Localizable.strings",
        "scripts/build.sh", "scripts/package.sh", "scripts/test.sh",
        ".github/workflows/ci.yml", ".github/workflows/release.yml",
    ]
    for name in required:
        if not (ROOT / name).is_file():
            errors.append(f"Missing required file: {name}")

    for workflow in (ROOT / ".github/workflows").glob("*.yml"):
        for action in re.findall(r"uses:\s*([^\s#]+)", workflow.read_text()):
            if not action.startswith("./") and not re.fullmatch(r"[^@]+@[0-9a-f]{40}", action):
                errors.append(f"Action must use a full commit SHA in {workflow.name}: {action}")

    changelog = (ROOT / "CHANGELOG.md").read_text()
    if not re.search(rf"^## {re.escape(version)}(?:\s|$)", changelog, re.MULTILINE):
        errors.append(f"CHANGELOG.md needs an entry for {version}")
    notes = ROOT / f"docs/releases/v{version}.md"
    if not notes.is_file():
        errors.append(f"Missing release notes: {notes.relative_to(ROOT)}")

    readme = (ROOT / "README.md").read_text()
    for expected in ("Speaker-Timer-<version>-macos-universal.dmg", "laixintao/tap/speaker-timer", "make release"):
        if expected not in readme:
            errors.append(f"README.md is missing: {expected}")

    markdown = list(ROOT.glob("*.md")) + list((ROOT / "docs").rglob("*.md"))
    for document in markdown:
        text = re.sub(r"```.*?```", "", document.read_text(), flags=re.DOTALL)
        for link in re.findall(r"\[[^\]\n]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)", text):
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc or link.startswith("#"):
                continue
            target = (document.parent / unquote(parsed.path)).resolve()
            if not target.exists():
                errors.append(f"Broken local link in {document.relative_to(ROOT)}: {link}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"PASS: project metadata for Speaker Timer {version}")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-tag")
    sys.exit(check(parser.parse_args().release_tag))
