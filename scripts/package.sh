#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -eq 0 ]] || { echo "Usage: scripts/package.sh" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/SpeakerTimer/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid app version: $VERSION" >&2; exit 1; }
NAME="Speaker-Timer-$VERSION-macos-universal"

"$PROJECT_ROOT/scripts/build.sh" Release universal
mkdir -p "$PROJECT_ROOT/dist"
STAGING_DIR="$(mktemp -d "$PROJECT_ROOT/dist/.package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$PROJECT_ROOT/build/Release-universal/Speaker Timer.app" "$STAGING_DIR/Speaker Timer.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/Speaker Timer.app" "$STAGING_DIR/$NAME.zip"

mkdir "$STAGING_DIR/image"
ditto "$STAGING_DIR/Speaker Timer.app" "$STAGING_DIR/image/Speaker Timer.app"
ln -s /Applications "$STAGING_DIR/image/Applications"
hdiutil create -quiet -volname "Speaker Timer" -srcfolder "$STAGING_DIR/image" \
    -format UDZO -fs HFS+ "$STAGING_DIR/$NAME.dmg"
hdiutil verify -quiet "$STAGING_DIR/$NAME.dmg"
(
    cd "$STAGING_DIR"
    shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS
)

rm -rf "$PROJECT_ROOT/dist/Speaker Timer.app"
rm -f "$PROJECT_ROOT"/dist/Speaker-Timer-*-universal.dmg "$PROJECT_ROOT"/dist/Speaker-Timer-*-universal.zip
for artifact in "Speaker Timer.app" "$NAME.dmg" "$NAME.zip" SHA256SUMS; do
    mv "$STAGING_DIR/$artifact" "$PROJECT_ROOT/dist/$artifact"
done
echo "Packaged: $PROJECT_ROOT/dist/$NAME.dmg"
echo "Packaged: $PROJECT_ROOT/dist/$NAME.zip"
