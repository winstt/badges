#!/usr/bin/env bash
# Sign (Developer ID) + notarize + staple a DMG so it runs on any Mac without
# Gatekeeper warnings. Run make-dmg.sh first.
#
#   ./scripts/notarize.sh dist/Badges-2.0.0.dmg
#
# One-time setup (needs a paid Apple Developer account):
#   1. Create a "Developer ID Application" certificate:
#        Xcode ▸ Settings ▸ Accounts ▸ (your Apple ID) ▸ Manage Certificates ▸ +
#      then confirm it's here:  security find-identity -v -p codesigning | grep "Developer ID"
#   2. Set project.yml CODE_SIGN_IDENTITY to "Developer ID Application" and rebuild the
#      DMG (or re-sign the .app below) — the app must be Developer-ID-signed AND
#      hardened-runtime (already ON in project.yml).
#   3. Store a notarytool credential profile once:
#        xcrun notarytool store-credentials badges-notary \
#          --apple-id "you@example.com" --team-id ATQ3U47NSK \
#          --password <app-specific-password from appleid.apple.com>
set -euo pipefail

DMG="${1:?usage: notarize.sh <path-to-dmg>}"
PROFILE="${NOTARY_PROFILE:-badges-notary}"

echo "▸ Submitting $DMG to Apple notary service…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "✓ Notarized + stapled: $DMG"
