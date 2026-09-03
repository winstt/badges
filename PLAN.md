# Badges — Master Plan

**Source of truth for scope and phases.** Update checkboxes as work lands.

macOS app that adds small file-type badge icons to file previews in Finder.
Rewrite of the 2025 "WorkFileBadges" prototype, done properly, released online.

## Locked decisions (2026-09-02)

| Decision | Choice |
|----------|--------|
| Distribution | **Direct from the web** — notarized DMG + landing page (Mac App Store = backlog) |
| Monetization | **Everything free + donate** (tip jar / GitHub Sponsors); revisit if traction |
| License | Open source (MIT) |
| Project setup | **XcodeGen** — `project.yml` is the project definition, `.xcodeproj` is generated |
| v1 badge set | The original 6 (psd, ai, pdf, svg, mp4, blend) + **user can add more formats in-app** |
| Naming | **Badges** everywhere. Targets: `Badges`, `BadgesFinderExt`, `BadgesThumbnail` |

## Architecture (recap)

- **Shared engine** (`Shared/`): `BadgeRule` (extensions → badge → corner), `BadgeStore`
  (App Group persistence, `<TeamID>.com.matyasnowak.badges`), `BadgeResolver` (matching),
  `BadgeImageLoader` (bundled asset or custom image from shared container).
- **FinderSync ext** (`FinderExt/`): free-platform path — one badge, bottom-right only
  (hard OS limit), works everywhere in Finder.
- **QuickLook thumbnail ext** (`Thumbnail/`): composites its own thumbnail — any of the
  4 corners + stacked badges (file-type + custom logo).
- **App** (`App/`): SwiftUI window managing the ruleset. Writes are eager → extensions
  read the same store, no IPC.

---

## Phase 0 — Toolchain ⚙️

- [x] Install Xcode (26.3 installed 2026-09-02)
- [x] `brew install xcodegen` (2.46.0 installed 2026-09-02)
- [x] `xcodegen generate` → `Badges.xcodeproj` builds from `project.yml`
- [x] First successful build of all 3 targets (ad-hoc signed, `xcodebuild ... build`
      → BUILD SUCCEEDED; both .appex embed correctly in Badges.app/Contents/PlugIns)
- [x] Team ID wired: `DEVELOPMENT_TEAM: ATQ3U47NSK` in project.yml + matching
      `appGroupID = "ATQ3U47NSK.com.matyasnowak.badges"` in BadgeStore.swift.
      Team ID came from the signing cert's OU (not the CN parenthetical). Verified:
      real-signed build, `codesign --verify` OK, app group embedded in both app and
      extension entitlements.
- [ ] `git init` + initial commit

## Phase 1 — Badge artwork & first light 🎨

Goal: see a badge on a .psd file in Finder.

- [x] 6 badge PNGs supplied by user (1024px, ~/Desktop/BADGES) and wired into
      `BadgeAssets.xcassets` — all 6 (psd, ai, pdf, svg, mp4, blend) verified baked
      into the extension's Assets.car after build
- [x] App built, signed, extension registered + enabled; old WorkFileBadges ext
      disabled (was conflicting — one FinderSync badge per file)
- [x] Downscale badge art to 128px at registration — 1024px source was too big for
      Finder to reliably render as a badge overlay (likely why only .ai "showed",
      and even that was the now-removed QuickLook composite)
- [x] **Made badging actually work** — see "FinderSync gotchas" below. requestBadgeIdentifier
      confirmed firing for all 6 types (fresh files) once the blockers were cleared.
- [x] **VERIFIED by user (2026-09-03):** all 6 badges (psd, ai, pdf, svg, mp4, blend)
      render in Finder; real previews intact. **PHASE 1 DONE.** ✅
- [ ] List view: FinderSync overlays the badge on the file's icon (left). User wants
      it visible in list view like the old version — confirm this is enough, or note
      that placing it on the right where color tags sit isn't possible via FinderSync

### ⚠️ RESUME HERE after Mac restart (2026-09-03)
User restarted the Mac mid-session. To get back to a working state:
1. Adobe re-enables its Finder extensions on every launch and they **block our badges**
   (see gotcha #3). After restart, disable BOTH:
   - `pluginkit -e ignore -i com.adobe.accmac.ACCFinderSync`
   - `pluginkit -e ignore -i com.adobe.acc.anc.AdobeCreativeCloud.AdobeContextMenuExtension`
2. Ensure ours is enabled: `pluginkit -e use -i com.matyasnowak.badges.finderext`
3. `killall Finder`. Badges should return. (App is installed at /Applications/Badges.app.)
4. If not showing, rebuild+redeploy: `cd ~/Badges && xcodebuild ... build` then
   `cp -R` the built app to /Applications (full dev loop in gotcha #4).

**NEXT UP = the Adobe coexistence problem** (the real release blocker). Options under
discussion: (1) in-app onboarding that detects the enabled Adobe FinderSync ext and
offers a one-click disable + explanation; (2) investigate whether it's a macOS limit on
concurrent FinderSync badge extensions rather than Adobe specifically, and whether ours
can win the slot; (3) document a manual "disable Adobe Finder integration" step. Decide,
then build. After that → Phase 2 (add-format UI).

### FinderSync gotchas (hard-won, 2026-09-03) — READ before touching the extension
1. **`ENABLE_DEBUG_DYLIB: NO`** (set in project.yml). Xcode 16+ wraps Debug builds in a
   "debug dylib" stub for previews. System-loaded extensions (FinderSync/QuickLook)
   start the process but the principal class **never inits** through that stub → dead
   extension, zero badges, no error. This wasted the most time.
2. **Sandboxed extension can't enumerate directories** (`contentsOfDirectory` →
   "Operation not permitted"). The *only* badging path is `requestBadgeIdentifier(for:)`,
   where Finder brokers per-URL access. No proactive scanning. (Sandbox is mandatory —
   an unsandboxed FinderSync extension doesn't load at all.)
3. **Adobe Creative Cloud "Core Sync" FinderSync monopolizes badge slots.** With
   `com.adobe.accmac.ACCFinderSync` enabled, Finder calls our requestBadgeIdentifier
   **0 times**; disable it → **57 times**. Real problem for Adobe users (i.e. our
   audience). Mitigation TBD — likely document + offer to toggle it, or investigate
   the FinderSync badge-extension limit. Test rig: `pluginkit -e ignore -i <id>`.
4. **Must run from /Applications**, not DerivedData — FinderSync is path-sensitive.
   Dev loop: build → `cp -R` to /Applications → `pluginkit -e use` → `killall Finder`.
5. **Triggering:** requestBadgeIdentifier only fires for items *drawn onscreen* in a
   frontmost window. `open` alone may not trigger it; `osascript ... activate` does.

## Phase 1.5 — Menu-bar UI ✅ (2026-09-03)

Moved the whole UI into the top bar as the primary surface. Uses the original
app's red "B" (extracted from `WorkFileBadges.app/Contents/Resources/AppIcon.icns`,
256px max — regen `MenuBarB` + `AppIcon` from a 1024 master later).

- [x] `MenuBarExtra(.window)` in `BadgesApp.swift`; app is now `LSUIElement` (no Dock icon)
- [x] Menu-bar glyph = colored "B" when active, dimmed/template when paused (`MenuBarLabel`)
- [x] `MenuPanel`: master switch + **scroll of per-badge on/off toggles** + Manage… / Donate / Quit
- [x] Master switch (`badgingEnabled`) in `BadgeStore` → `BadgeResolver` returns nothing when off
- [x] Extension picks up toggles/master live via cross-process KVO on the shared suite
      (`FinderSync.observeValue` → `reload()` re-registers). Finder repaints on next scroll/refresh.
- [x] `MenuBarB` (18/36/54) + `AppIcon` (16–512@2x) assets added; builds + deployed to /Applications
- [x] **Menu-bar glyph is now MONOCHROME** — uses the user's real `b logo.png`
      (`shared/b-logo.png`), converted to a template glyph (darkness→alpha, cropped).
      `template-rendering-intent: template`, rendered `.template` → white on dark bar.
      The **red** "B" is kept **only as the app icon** (+ shown in the panel header).
- [x] **Badge cache refresh — CONFIRMED WORKING by user (2026-09-03).** Extension
      `reload()` re-asserts `directoryURLs` ([] → ["/"]) to force Finder to re-query;
      manual **Refresh** button in the panel; full flush = relaunch Finder.

## Phase 1.6 — Monorepo + cross-platform readiness 🗂️ (2026-09-03)

Decision (user): **ship macOS first, but structure the repo monorepo-ready now** so
Windows/Linux can be added later without a rebuild. FinderSync is macOS-only — each
platform is a separate native shell integration; they share only a portable ruleset.

- [x] Restructured to `platforms/{macos,windows,linux}` + `shared/`. macOS sources
      moved under `platforms/macos/` (xcodegen regenerated there; **build still SUCCEEDS**).
- [x] `shared/schema/rules.schema.json` (portable ruleset schema) + `shared/rules.default.json`
      (the original 6) + `shared/badges/*.png` (1024px masters) + `shared/b-logo.png`.
- [x] Top-level `README.md` (monorepo + platform table), `LICENSE` (MIT),
      `platforms/{windows,linux}/README.md` design briefs, `platforms/macos/README.md`.
- [x] `.gitignore` updated (`**/*.xcodeproj/`).
- [ ] `git init` + first commit, create public GitHub repo `badges`, push.
- [ ] **Blocker for DMG:** only an *Apple Development* cert is present — need a
      **Developer ID Application** cert (create in the paid Apple Developer account)
      before notarize + DMG. Landing page after.

## Phase 2 — Rule management (the "add formats" core) ➕

Goal: user adds any format without us shipping an update.

- [x] "Add format" sheet (`AddFormatSheet.swift`): name + extension list + badge picker
      (bundled badges **or import own PNG** via `.fileImporter`). In the manager window.
- [x] Custom image import → `BadgeStore.importCustomBadge(from:)` copies into App Group
      `CustomBadges/` (security-scoped read from the open panel). `deleteCustomBadge` GCs
      orphans on rule delete.
- [x] **Delete** existing rules (right-click row → Delete in the manager window).
- [x] **Live reload** — done in Phase 1.5 via cross-process KVO in `FinderSync.observeValue`.
- [x] Duplicate-extension **conflict warning** in the sheet (`conflictingExtensions`).
- [ ] **Edit** existing rules + drag to **reorder** (priority) — not done yet.
- [ ] Empty state / no-matching-image polish.

## ~~Phase 3 — QuickLook layer (corners + stacking)~~ ❌ SHELVED (2026-09-02)

**Removed from the product.** The QuickLook thumbnail extension composites a type
*icon* + badge, which **replaces the real content preview** — user can't see what's
inside psd/pdf/etc anymore. That's a regression the whole point of the old app avoided.
Also produced inconsistent results (only some types rendered). Decision: go **pure
FinderSync** like the original working version. Corner placement / stacking are not
worth losing real previews. If revisited, it must render the *actual* file preview
(PDFKit/CGImageSource per format) as the base, not the type icon — much bigger job.
Consequently the corner picker was removed from the app UI (FinderSync gives us no
placement control anyway).

<details><summary>Original Phase 3 plan (kept for reference)</summary>

## Phase 3 — QuickLook layer (corners + stacking) ✨

Goal: badge in any corner, two badges stacked (type + personal/company logo).

- [ ] Wire `BadgesThumbnail` UTIs to actual rule set (keep `QLSupportedContentTypes`
      in sync with rules; document which types we take over from system previews)
- [ ] Verify compositing on psd/pdf/svg/ai; tune badge ratio (currently 38%) + inset
- [ ] Stacking: multiple rules matching one file render in their configured corners
- [ ] Understand + document the tradeoff: our thumbnail replaces the system preview
      for those UTIs (base = file's own icon). Decide per-type default: badge-on-icon
      vs badge-on-real-preview (real preview would need rendering psd/pdf ourselves —
      PDF/image feasible via PDFKit/CGImageSource; psd = icon only)
- [ ] In-app corner picker already exists → make the QuickLook hint clear in UI

</details>

## Phase 4 — Onboarding & polish 💅

- [ ] First-run onboarding: 1) what it does (visual demo), 2) enable-extension guide
      with live status detection (`pluginkit -m -i com.matyasnowak.badges.finderext`),
      3) drop a sample file to see it work
- [ ] App icon + visual identity — the swag/culture design pass (this is the brand:
      design × tech crossover, make it feel like merch, not a utility)
- [ ] Menu bar presence? (decide: pure window app vs menu-bar quick toggle)
- [ ] Wire the Donate button to the real link (GitHub Sponsors / Buy Me a Coffee)
- [ ] Copy pass (EN first; CZ later if wanted)

## Phase 5 — Release engineering 📦

- [ ] Public GitHub repo (`badges`), MIT LICENSE, README with screenshots/GIF
- [ ] GitHub Sponsors / BMC set up → Donate links in app + repo
- [ ] Developer ID Application certificate (paid Apple Developer account required —
      already had one for the 2025 build)
- [ ] Archive → `notarytool submit` → staple; hardened runtime is already ON in
      project.yml
- [ ] DMG packaging (`create-dmg`) with drag-to-Applications layout
- [ ] Optional: Sparkle auto-updates (appcast on GitHub Pages) — nice-to-have, not a
      launch blocker
- [ ] Smoke test on a clean user account / second Mac: install from DMG, enable, badge

## Phase 6 — Launch 🚀

- [ ] Landing page (GitHub Pages like EGORITHM, or Vercel): hero GIF of Finder with
      badges, download button, donate, open source link
- [ ] Demo GIF/video (screen record Finder before/after)
- [ ] Send to Maty Sochor + Adam (startup feedback), Mikhail (producer angle —
      would music-file badges land? wav/mp3/flp)
- [ ] Post: X/Twitter, Product Hunt, r/macapps, designer communities
- [ ] Collect feedback → decide startup phase / next bets

---

## Backlog (explicitly not v1)

- Music producer set: wav, mp3, aiff, flp (FL Studio), als (Ableton), mov
- Transparent-.mov detection (AVFoundation alpha-channel check) — badge transparent
  videos differently from normal ones
- Real-preview compositing for PDF/images in QuickLook layer
- Folder badges (project folders with client logos)
- Per-folder / per-project rule scoping
- Mac App Store release (needs StoreKit-less free app or IAP rethink)
- Monetization (company/trademark tier) — only if traction says so

## Known risks

1. **FinderSync badge slot is contested** — Dropbox/iCloud/OneDrive also badge files;
   only one FinderSync badge shows per file. Test coexistence early (Phase 1).
2. **Extension live-reload** is the trickiest engineering bit (Phase 2) — FinderSync
   caches badge registrations; plan a re-registration path before building the UI on
   top of it.
3. **QuickLook takeover tradeoff** (Phase 3) — replacing system previews for psd/ai
   may feel like a regression; keep the QL layer opt-in per rule (corner ≠ bottom-right
   is the opt-in signal).
4. **macOS updates** can shift FinderSync behavior; original targeted macOS 14.6+,
   we keep that floor.
