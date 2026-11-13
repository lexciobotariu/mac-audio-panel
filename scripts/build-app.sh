#!/usr/bin/env bash
# Builds build/MacAudioPanel.app from the Swift package and signs it.
#
# Environment (all optional):
#   SIGN_IDENTITY  codesign identity, e.g. "Developer ID Application: Name (TEAMID)".
#                  Defaults to "-" (ad hoc), fine for local use.
#   VERSION        marketing version written into Info.plist, e.g. 1.0.0
#   CONFIG         swift build configuration (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c "$CONFIG" --product MacAudioPanel

APP="build/MacAudioPanel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/MacAudioPanel" "$APP/Contents/MacOS/MacAudioPanel"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ -n "${VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "${BUILD_NUMBER:-$VERSION}" "$APP/Contents/Info.plist"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  # Developer ID: hardened runtime and a secure timestamp are required for notarization.
  codesign --force --options runtime --timestamp \
    --entitlements Resources/MacAudioPanel.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
fi

codesign --verify --strict --verbose=1 "$APP"
echo "Built $APP (signed with: $SIGN_IDENTITY)"
