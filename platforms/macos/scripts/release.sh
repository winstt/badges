#!/usr/bin/env bash
# One-shot release: archive → Developer-ID export → notarize the app → package a
# drag-to-Applications DMG → notarize + staple the DMG.
#
#   NOTARY_PROFILE=badges-notary ./scripts/release.sh
#
# Prerequisites (one-time — see RELEASING.md), all needing a *paid* Apple Developer
# account:
#   1. A "Developer ID Application" certificate in your login keychain:
#        security find-identity -v -p codesigning | grep "Developer ID Application"
#   2. A stored notarytool credential profile (default name: badges-notary):
#        xcrun notarytool store-credentials badges-notary \
#          --apple-id you@example.com --team-id <TEAM_ID> --password <app-specific-pw>
#   3. If your paid Team ID is NOT ATQ3U47NSK, set TEAM_ID below AND update
#      DEVELOPMENT_TEAM (project.yml) + appGroupID (BadgeStore.swift) to match, or the
#      shared App Group breaks and the extension can't read the ruleset.
set -euo pipefail

cd "$(dirname "$0")/.."                         # platforms/macos
ROOT="$(pwd)"
SCHEME="Badges"
TEAM_ID="${TEAM_ID:-ATQ3U47NSK}"
NOTARY_PROFILE="${NOTARY_PROFILE:-badges-notary}"

BUILD="$ROOT/.build-release"
ARCHIVE="$BUILD/Badges.xcarchive"
EXPORT="$BUILD/export"
DIST="$ROOT/dist"
OPTS="$ROOT/scripts/exportOptions-developer-id.plist"

echo "-- Preflight"
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || { echo "✗ No 'Developer ID Application' certificate found. See RELEASING.md step 2."; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || { echo "✗ notarytool profile '$NOTARY_PROFILE' not set. See RELEASING.md step 3."; exit 1; }

echo "-- Generating project"
xcodegen generate >/dev/null

echo "-- Archiving (Release)"
rm -rf "$BUILD"; mkdir -p "$BUILD"
xcodebuild -project Badges.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  archive >/dev/null

echo "-- Exporting Developer ID app"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTS" -exportPath "$EXPORT" >/dev/null
APP="$EXPORT/Badges.app"
[ -d "$APP" ] || { echo "✗ Export produced no Badges.app"; exit 1; }

echo "   signed by: $(codesign -dvv "$APP" 2>&1 | grep -i 'Authority=' | head -1)"
codesign --verify --deep --strict "$APP" && echo "   codesign --verify OK"

echo "-- Notarizing the app"
ZIP="$BUILD/Badges.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Badges-$VERSION.dmg"
mkdir -p "$DIST"; rm -f "$DMG"

echo "-- Packaging $DMG"
STAGE="$(mktemp -d)"; cp -R "$APP" "$STAGE/"
create-dmg \
  --volname "Badges $VERSION" \
  --window-pos 200 120 --window-size 520 360 --icon-size 100 \
  --icon "Badges.app" 140 180 --app-drop-link 380 180 --no-internet-enable \
  "$DMG" "$STAGE" >/dev/null || { [ -f "$DMG" ] || { echo "✗ create-dmg failed"; exit 1; }; }
rm -rf "$STAGE"

echo "-- Notarizing + stapling the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✓ Release ready: $DMG"
echo "  Test on another Mac: it should open with a double-click, no Gatekeeper warning."
