#!/usr/bin/env bash
# Build Debug, install into /Applications, and keep Launch Services clean so the OS
# always launches THIS copy (not a stale DerivedData one).
#
#   ./scripts/dev-deploy.sh
#
# Why: every Xcode build drops a Badges.app in DerivedData that also registers with
# Launch Services. With several around, Spotlight/Finder may open an old one — you
# think you're launching the new build but you're not. This builds to a local
# DerivedData dir, copies to /Applications, then *unregisters* that build copy.
set -euo pipefail

cd "$(dirname "$0")/.."                      # platforms/macos
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DD="$PWD/.dd"

echo "-- Building"
xcodegen generate >/dev/null
xcodebuild -project Badges.xcodeproj -scheme Badges -configuration Debug \
    -derivedDataPath "$DD" -destination 'platform=macOS' build >/dev/null
APP="$DD/Build/Products/Debug/Badges.app"

echo "-- Installing to /Applications"
osascript -e 'quit app "Badges"' 2>/dev/null || true
sleep 1
rm -rf /Applications/Badges.app
cp -R "$APP" /Applications/Badges.app

echo "-- Launch Services hygiene"
"$LSREGISTER" -u "$APP" 2>/dev/null || true          # drop the build copy
"$LSREGISTER" -f /Applications/Badges.app 2>/dev/null || true

echo "-- Enabling extension + relaunching"
pluginkit -e use -i com.matyasnowak.badges.finderext 2>/dev/null || true
open /Applications/Badges.app
sleep 2
killall Finder 2>/dev/null || true

echo "OK. Only registered copy:"
mdfind "kMDItemCFBundleIdentifier == 'com.matyasnowak.badges'" 2>/dev/null || true
