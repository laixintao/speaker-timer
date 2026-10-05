#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
./scripts/build.sh Debug native

TEST_APP="$PROJECT_ROOT/build/Tests/SpeakerTimerTests.app"
rm -rf "$TEST_APP"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources" build/qa build/ModuleCache
rm -f build/qa/*.png
cp SpeakerTimer/Info.plist "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.xbin.speaker-timer.tests' "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable SpeakerTimerTests' "$TEST_APP/Contents/Info.plist"
cp -R SpeakerTimer/Resources/. "$TEST_APP/Contents/Resources/"

xcrun swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
    -target "$(uname -m)-apple-macosx14.0" \
    -sdk "$(xcrun --show-sdk-path)" \
    -module-cache-path build/ModuleCache \
    SpeakerTimer/Models.swift SpeakerTimer/DurationFormat.swift SpeakerTimer/TimerEngine.swift \
    SpeakerTimer/PlanStore.swift SpeakerTimer/TimerViews.swift SpeakerTimer/EditorView.swift \
    SpeakerTimer/OverlayPanelController.swift Tests/SmokeTests.swift \
    -o "$TEST_APP/Contents/MacOS/SpeakerTimerTests"

codesign --force --sign - "$TEST_APP"
"$TEST_APP/Contents/MacOS/SpeakerTimerTests" -AppleLanguages '(en)'
