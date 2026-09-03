#!/usr/bin/env bash
# Build a Release Badges.app and package it into a drag-to-Applications .dmg.
#
#   ./scripts/make-dmg.sh
#
# Output: dist/Badges-<version>.dmg  (version comes from MARKETING_VERSION).
#
# NOTE: This packages whatever signing xcodebuild produces. For a DMG that runs on
# *other* people's Macs you must sign with a **Developer ID Application** cert and
# notarize (see notarize.sh) — a Development-signed build only launches on your own
# registered machines, and ad-hoc signing breaks the Team-ID-prefixed App Group that
# the app and the Finder extension use to share the ruleset.
set -euo pipefail

cd "$(dirname "$0")/.."                    # platforms/macos
ROOT="$(pwd)"
DIST="$ROOT/dist"
BUILD="$ROOT/.build-dmg"
SCHEME="Badges"

echo "-- Generating project + building Release"
xcodegen generate >/dev/null
xcodebuild -project Badges.xcodeproj -scheme "$SCHEME" -configuration Release \
    -derivedDataPath "$BUILD" -destination 'platform=macOS' \
    clean build >/dev/null

APP="$BUILD/Build/Products/Release/Badges.app"
[ -d "$APP" ] || { echo "✗ Build produced no Badges.app"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Badges-$VERSION.dmg"
mkdir -p "$DIST"
rm -f "$DMG"

echo "-- Packaging ${DMG}"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"

create-dmg \
    --volname "Badges $VERSION" \
    --window-pos 200 120 --window-size 520 360 \
    --icon-size 100 \
    --icon "Badges.app" 140 180 \
    --app-drop-link 380 180 \
    --no-internet-enable \
    "$DMG" "$STAGE" >/dev/null || {
        # create-dmg returns non-zero if it can't set a custom volume icon; the DMG
        # is still produced. Only fail if the file is genuinely missing.
        [ -f "$DMG" ] || { echo "✗ create-dmg failed"; exit 1; }
    }
rm -rf "$STAGE"

echo "✓ $DMG"
echo "  codesign: $(codesign -dv "$APP" 2>&1 | grep -i 'Authority=' | head -1 || echo 'unsigned/ad-hoc')"
