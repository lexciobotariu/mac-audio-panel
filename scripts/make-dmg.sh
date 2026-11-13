#!/usr/bin/env bash
# Packs build/MacAudioPanel.app into build/MacAudioPanel-<version>.dmg with an
# Applications shortcut. Signs the DMG when SIGN_IDENTITY is a real identity.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MacAudioPanel.app"
[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DMG="build/MacAudioPanel-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Mac Audio Panel" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "$DMG"
