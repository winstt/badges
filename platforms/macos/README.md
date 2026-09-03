# Badges — macOS

Native macOS app: a menu-bar utility + a **FinderSync** extension that paints
file-type badges onto icons in Finder.

## Layout
- `App/` — SwiftUI menu-bar app (`MenuBarExtra`, the panel with per-badge toggles).
- `FinderExt/` — the FinderSync app extension that Finder loads to draw badges.
- `Shared/` — engine shared by both targets (rules, store, resolver, image loader).
- `BadgeAssets.xcassets/` — bundled badge art + the monochrome menu-bar `B` + `AppIcon`.
- `project.yml` — XcodeGen definition; `.xcodeproj` is generated (git-ignored).

## Build & run
```sh
brew install xcodegen          # once
cd platforms/macos
xcodegen generate
xcodebuild -project Badges.xcodeproj -scheme Badges -configuration Debug build
```

## Dev deploy loop (FinderSync is path-sensitive — must run from /Applications)
```sh
APP=$(xcodebuild -project Badges.xcodeproj -scheme Badges -showBuildSettings \
        | awk -F' = ' '/ TARGET_BUILD_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')
cp -R "$APP" /Applications/Badges.app
pluginkit -e use -i com.matyasnowak.badges.finderext
killall Finder
```

## Gotchas (hard-won — read before touching the extension)
1. `ENABLE_DEBUG_DYLIB: NO` (in `project.yml`) — else the extension process starts but
   its principal class never inits → no badges, no error.
2. Sandboxed extension **can't enumerate directories**; the only badging path is
   `requestBadgeIdentifier(for:)`.
3. Adobe Creative Cloud's FinderSync monopolises badge slots — disable
   `com.adobe.accmac.ACCFinderSync` (and the ACC context-menu ext) to coexist.
4. Must run from `/Applications`, not DerivedData.

## Cross-platform
The ruleset is portable — see [`../../shared/`](../../shared). Keep `Shared/BadgeRule`
in sync with `shared/schema/rules.schema.json`.
