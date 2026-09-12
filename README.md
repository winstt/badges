<div align="center">
  <img src="shared/app-icon.png" width="128" alt="Badges app icon">
  <h1>Badges</h1>
  <p><strong>A Finder extension that adds a badge system to your file formats.</strong><br>
  Small type-badges on file previews, so you can tell a <code>.psd</code> from a
  <code>.png</code> at a glance — without opening anything.</p>
</div>

---

Badges started as a way to visually tell apart lookalike files — a `.psd` from a `.png`,
a working file from an export — right in the Finder window you're already looking at. It
grew into a small system for **assigning icons to the formats you work with**.

- **Flexibility** — badge any format you like, not a fixed list.
- **Organization** — see project files by kind at a glance, no opening required.
- **Customization** — use the built-in badges, generate your own on-brand ones, or
  upload your own art.

It's a native **FinderSync** extension (one badge per file, drawn by Finder — it never
replaces the real preview) with a menu-bar app to manage everything. **Free** and open
source (MIT).

## Supported formats

| Category | Formats |
|----------|---------|
| **Graphics** | Photoshop (`.psd` `.psb`), Illustrator (`.ai`), After Effects (`.aep`), Premiere (`.prproj`), PDF (`.pdf`), SVG (`.svg`) |
| **Music** | MP3 (`.mp3`), WAV (`.wav`), FL Studio (`.flp`) |
| **Video** | MP4 (`.mp4`), MKV (`.mkv`), MOV (`.mov`) |
| **Images** | PNG (`.png`), HEIC (`.heic`) |
| **3D** | Blender (`.blend`) |

**➕ Add more, anytime.** Any extension you want, with a badge you **generate in-app**
(house-style card + your colours + label) or **upload** yourself — no app update needed.

## Try it (macOS)

> **Heads up:** there's **no one-click download yet.** Until the app is notarized
> with an Apple *Developer ID*, a prebuilt binary won't launch on someone else's Mac
> (Gatekeeper blocks it). So for now Badges is **build-from-source** — a bit technical,
> but ~2 minutes if you're comfortable in the terminal. A signed `.dmg` is coming.

You need macOS 14.6+ and **full Xcode** installed (not just Command Line Tools).

```sh
# 1. tools
brew install xcodegen
xcode-select --install                      # if you don't have Xcode CLTs

# 2. get the code
git clone https://github.com/winstt/badges.git
cd badges/platforms/macos

# 3. build
xcodegen generate
xcodebuild -project Badges.xcodeproj -scheme Badges -configuration Release build

# 4. install into /Applications (FinderSync only loads from there)
APP=$(xcodebuild -project Badges.xcodeproj -scheme Badges -configuration Release \
        -showBuildSettings | awk -F' = ' \
        '/ TARGET_BUILD_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')
cp -R "$APP" /Applications/Badges.app
open /Applications/Badges.app
```

Then enable the extension in **System Settings → General → Login Items & Extensions
→ Finder**, and look for the **B** in your menu bar. Badges show on matching files
in Finder.

> Using Adobe Creative Cloud? Its Finder extension can hog the badge slot — turn off
> *Core Sync* under the same Extensions pane if badges don't appear. (Badges detects
> this and links you straight there.)

## Status

macOS is working and in active development. Next milestone: **Developer ID signing →
notarized `.dmg` → landing page** so anyone can install it with a double-click (see
[PLAN.md](PLAN.md)).
