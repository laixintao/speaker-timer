#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -eq 0 ]] || { echo "Usage: scripts/test-package.sh (run package.sh first)" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/SpeakerTimer/Info.plist")"
DIST_DIR="$PROJECT_ROOT/dist"
NAME="Speaker-Timer-$VERSION-universal"
mkdir -p "$PROJECT_ROOT/build/Tests"
TEST_DIR="$(mktemp -d "$PROJECT_ROOT/build/Tests/package.XXXXXX")"
MOUNT_POINT="$TEST_DIR/mounted"

cleanup() {
    if [[ -d "$MOUNT_POINT/Speaker Timer.app" ]]; then hdiutil detach -quiet "$MOUNT_POINT"; fi
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

verify_app() {
    local app="$1"
    local executable="$app/Contents/MacOS/SpeakerTimer"
    [[ -x "$executable" ]]
    codesign --verify --strict --all-architectures "$app"
    xcrun lipo "$executable" -verify_arch arm64 x86_64
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$VERSION" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")" == "14.0" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "io.xbin.speaker-timer" ]]
    [[ -s "$app/Contents/Resources/SpeakerTimer.icns" ]]
    cmp "$PROJECT_ROOT/LICENSE" "$app/Contents/Resources/LICENSE"
    plutil -lint "$app/Contents/Resources/en.lproj/Localizable.strings"
    diff -qr "$DIST_DIR/Speaker Timer.app" "$app"
}

(cd "$DIST_DIR" && shasum -a 256 -c SHA256SUMS)
verify_app "$DIST_DIR/Speaker Timer.app"
ditto -x -k "$DIST_DIR/$NAME.zip" "$TEST_DIR/unzipped"
verify_app "$TEST_DIR/unzipped/Speaker Timer.app"
hdiutil verify -quiet "$DIST_DIR/$NAME.dmg"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DIST_DIR/$NAME.dmg"
verify_app "$MOUNT_POINT/Speaker Timer.app"
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]]
hdiutil detach -quiet "$MOUNT_POINT"
echo "PASS: checksums, universal binary, ZIP/DMG round trips, signature, resources, and install shortcut"
