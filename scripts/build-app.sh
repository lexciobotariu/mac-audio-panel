#!/usr/bin/env bash
# Builds build/MacAudioPanel.app from the Swift package and signs it ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product MacAudioPanel

APP="build/MacAudioPanel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/MacAudioPanel" "$APP/Contents/MacOS/MacAudioPanel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
