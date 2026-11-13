#!/usr/bin/env bash
# Notarizes and staples a DMG. Needs an app-specific password for the Apple ID.
#
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   (environment)
#   scripts/notarize.sh build/MacAudioPanel-1.0.0.dmg
set -euo pipefail

DMG="${1:?usage: notarize.sh <dmg>}"
: "${APPLE_ID:?set APPLE_ID}" "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}" "${APPLE_APP_PASSWORD:?set APPLE_APP_PASSWORD}"

xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" \
  --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarized $DMG"
