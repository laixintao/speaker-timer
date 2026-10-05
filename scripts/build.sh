#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Release}"
ARCHITECTURE="${2:-native}"

usage() {
    echo "Usage: scripts/build.sh [Debug|Release] [native|universal|arm64|x86_64]" >&2
    exit 1
}

[[ $# -le 2 ]] || usage
case "$CONFIGURATION" in
    Debug) SWIFT_FLAGS=(-Onone -g -D DEBUG) ;;
    Release) SWIFT_FLAGS=(-O) ;;
    *) usage ;;
esac

BUILD_DIR="$PROJECT_ROOT/build/$CONFIGURATION"
case "$ARCHITECTURE" in
    native) ARCHITECTURES=("$(uname -m)") ;;
    universal) ARCHITECTURES=(arm64 x86_64); BUILD_DIR+="-universal" ;;
    arm64|x86_64) ARCHITECTURES=("$ARCHITECTURE"); BUILD_DIR+="-$ARCHITECTURE" ;;
    *) usage ;;
esac

mkdir -p "$BUILD_DIR" "$PROJECT_ROOT/build/ModuleCache"
if [[ ! -s "$PROJECT_ROOT/SpeakerTimer/Resources/SpeakerTimer.icns" ]]; then
    (cd "$PROJECT_ROOT" && xcrun swift -module-cache-path "$PROJECT_ROOT/build/ModuleCache" scripts/MakeIcon.swift)
fi

STAGING_DIR="$(mktemp -d "$BUILD_DIR/.build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/Speaker Timer.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

SDK_PATH="$(xcrun --show-sdk-path)"
BINARIES=()
for arch in "${ARCHITECTURES[@]}"; do
    binary="$STAGING_DIR/SpeakerTimer-$arch"
    xcrun swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors \
        -target "$arch-apple-macosx14.0" -sdk "$SDK_PATH" \
        -module-cache-path "$PROJECT_ROOT/build/ModuleCache" \
        -module-name SpeakerTimer "${SWIFT_FLAGS[@]}" \
        "$PROJECT_ROOT"/SpeakerTimer/*.swift -o "$binary"
    BINARIES+=("$binary")
done

if [[ ${#BINARIES[@]} -eq 1 ]]; then
    cp "${BINARIES[0]}" "$APP_DIR/Contents/MacOS/SpeakerTimer"
else
    xcrun lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/SpeakerTimer"
fi

cp "$PROJECT_ROOT/SpeakerTimer/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$PROJECT_ROOT/SpeakerTimer/Resources/." "$APP_DIR/Contents/Resources/"
cp "$PROJECT_ROOT/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
plutil -lint "$APP_DIR/Contents/Info.plist" "$APP_DIR/Contents/Resources/en.lproj/Localizable.strings"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict --all-architectures "$APP_DIR"

rm -rf "$BUILD_DIR/Speaker Timer.app"
mv "$APP_DIR" "$BUILD_DIR/Speaker Timer.app"
echo "Built: $BUILD_DIR/Speaker Timer.app"
