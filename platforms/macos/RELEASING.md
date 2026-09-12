# Releasing Badges (notarized .dmg)

Goal: a `Badges-<version>.dmg` that opens with a **double-click on any Mac**, no
Gatekeeper warning. That requires a **Developer ID Application** certificate (paid Apple
Developer Program) + **notarization**. Ad-hoc / free "Apple Development" signing only runs
on your own registered machines and can't be distributed.

## One-time setup (needs the paid account)

1. **Enroll** in the Apple Developer Program — <https://developer.apple.com/programs/>
   ($99/yr). Individual is fine.

2. **Create a "Developer ID Application" certificate**
   Xcode → Settings → Accounts → *your Apple ID* → **Manage Certificates** → **+** →
   *Developer ID Application*. Verify:
   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

3. **Confirm the Team ID.** Check the new cert's team:
   ```sh
   security find-identity -v -p codesigning
   ```
   The default here is **ATQ3U47NSK** (also the App Group prefix). If your paid
   membership's Team ID is different, update **both**:
   - `project.yml` → `DEVELOPMENT_TEAM`
   - `Shared/BadgeStore.swift` → `appGroupID` (`<TeamID>.com.matyasnowak.badges`)

   and re-run `xcodegen generate`. Otherwise the shared App Group breaks and the Finder
   extension can't read the ruleset. Then pass `TEAM_ID=<yours>` to the release script.

4. **Store notarization credentials** (app-specific password from
   <https://appleid.apple.com> → Sign-In & Security → App-Specific Passwords):
   ```sh
   xcrun notarytool store-credentials badges-notary \
     --apple-id nowakmatyas@gmail.com --team-id ATQ3U47NSK --password <app-specific-pw>
   ```

## Cut a release

```sh
cd platforms/macos
NOTARY_PROFILE=badges-notary ./scripts/release.sh      # add TEAM_ID=... if it changed
```

This archives → exports a Developer-ID-signed app → notarizes & staples the app →
packages `dist/Badges-<version>.dmg` → notarizes & staples the DMG. First notarization
can take a few minutes.

Bump the version in `project.yml` (`MARKETING_VERSION`) before releasing.

## Verify

```sh
spctl -a -vvv -t install dist/Badges-<version>.dmg     # should say "accepted / Notarized Developer ID"
```
Best test: open the DMG on a **different** Mac, drag to Applications, launch, then enable
the extension in System Settings → General → Login Items & Extensions → Finder.

## Publish

Attach the `.dmg` to a GitHub Release (tag e.g. `v2.0.0`) and link it from the README /
landing page.
