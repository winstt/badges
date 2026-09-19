# Shipping Badges to the Mac App Store

Badges already meets the big MAS requirement: it's **sandboxed**, uses an App Group
(via `$(TeamIdentifierPrefix)`), declares a category, and has a version + build number.
FinderSync extensions are allowed on the MAS (e.g. TaskBadges ships there).

## 0. Buy the membership

Apple Developer Program, $99/yr — <https://developer.apple.com/programs/enroll/>
(or the **Apple Developer** app on iPhone/iPad → Account → Enroll). Individual is fine.
Needs 2FA on the Apple ID. Enrollment can take minutes to ~48 h.

## 1. Confirm the Team ID  ⚠️

After enrolling, note your Team ID (<https://developer.apple.com/account> → Membership).
The App Group prefix is currently hardcoded as **ATQ3U47NSK**:
- `Shared/BadgeStore.swift` → `appGroupID = "ATQ3U47NSK.com.matyasnowak.badges"`

The entitlement itself uses `$(TeamIdentifierPrefix)` so it adapts automatically, but the
**Swift constant must match the signing team**. If your paid Team ID differs from
ATQ3U47NSK, update that constant (and `DEVELOPMENT_TEAM` in `project.yml`), then
`xcodegen generate`. Otherwise the app and its Finder extension can't share the ruleset.

## 2. Register the App ID + App Group

Easiest via Xcode automatic signing (it creates them for you on first archive). Or in the
developer portal: Identifiers →
- App IDs: `com.matyasnowak.badges` and `com.matyasnowak.badges.finderext`
  (enable **App Groups** capability on both)
- App Groups: `<TeamID>.com.matyasnowak.badges`

## 3. Create the app record in App Store Connect

<https://appstoreconnect.apple.com> → Apps → **+** → New App
- Platform: macOS · Name: **Badges** · Primary language · Bundle ID:
  `com.matyasnowak.badges` · SKU: anything (e.g. `badges-mac`)
- Price: **Free**

## 4. Archive & upload

In Xcode (open `Badges.xcodeproj`, or run `xcodegen generate` first):
1. Xcode → Settings → Accounts → add your Apple ID (the paid team).
2. Scheme **Badges**, destination **My Mac**, signing **Automatic** (already set).
3. Bump `CURRENT_PROJECT_VERSION` in `project.yml` for each new upload (must increase);
   re-run `xcodegen generate`.
4. **Product → Archive** → Organizer → **Distribute App** → **App Store Connect** →
   **Upload**. Xcode signs with *Apple Distribution* + a Mac App Store profile and
   uploads the build. (No notarization needed for MAS — Apple handles it.)

## 5. Fill metadata & submit

In App Store Connect, on the new version:
- Screenshots (macOS, 1280×800 or 2560×1600) — a Finder window showing badges + the app.
- Description, keywords, subtitle, support URL (GitHub), privacy policy URL.
- **App Privacy**: Badges collects **no data** — declare "Data Not Collected".
- **Review notes** (important for a Finder extension) — see below.
- Submit for review.

### Suggested review note
> Badges is a Finder Sync extension that overlays a small file-type badge on files in
> Finder (e.g. a PSD vs PNG marker), based on user-configured rules. It reads only file
> URLs/extensions to choose an icon — no file contents, no data collection, no network.
> Enable it under System Settings → General → Login Items & Extensions → Finder.

## Notes / risks

- Review may ask why the extension observes the whole filesystem (`directoryURLs = ["/"]`
  + mounted volumes): it's so badges appear anywhere the user browses; badging reads no
  file contents. The review note above pre-empts this.
- Auto-updates come free via the App Store (no Sparkle needed).
- Direct-DMG path (`release.sh` / `RELEASING.md`) still works if you also want an
  off-store download later; MAS and Developer ID can coexist.
