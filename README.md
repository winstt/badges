<div align="center">
  <img src="shared/b-logo.png" width="96" alt="Badges logo">
  <h1>Badges</h1>
  <p><strong>File-type badges for your file manager.</strong> Small icons on file
  previews so you can tell a <code>.psd</code> from an <code>.ai</code> from a
  <code>.blend</code> at a glance — without opening anything.</p>
</div>

---

Badges overlays a little type-badge on files in your OS file browser. It's the
designer/producer utility the built-in generic icons never gave you: see project
files by kind, right in the window you're already looking at.

- **Free** and open source (MIT). Donate if it saves you time.
- One badge per file, drawn by the OS file browser (never replaces the real preview).
- Add your own formats and badges (no app update needed).

## Platforms

| Platform | Mechanism | Status |
|----------|-----------|--------|
| **macOS** | FinderSync extension | ✅ Working — [`platforms/macos`](platforms/macos) |
| **Windows** | Explorer icon overlay handler | 🔜 Planned — [`platforms/windows`](platforms/windows) |
| **Linux** | Nautilus / Dolphin extensions | 🔜 Planned — [`platforms/linux`](platforms/linux) |

Each platform is a native shell integration (they can't share UI code), but they all
read **one portable ruleset** so behaviour and artwork stay in sync.

## Repo layout

```
platforms/
  macos/     SwiftUI menu-bar app + FinderSync extension  (built)
  windows/   design brief for the Explorer overlay handler
  linux/     design brief for the file-manager extensions
shared/
  rules.default.json        the default ruleset (the original 6 badges)
  schema/rules.schema.json  portable ruleset schema every platform reads
  badges/                   1024px badge master art (psd, ai, pdf, svg, mp4, blend)
PLAN.md      roadmap / source of truth for scope + phases
```

## macOS quick start

```sh
brew install xcodegen
cd platforms/macos && xcodegen generate
xcodebuild -project Badges.xcodeproj -scheme Badges build
```

Full build/deploy/gotchas: [`platforms/macos/README.md`](platforms/macos/README.md).

## Status

macOS is working and in active development; a notarized DMG + landing page are the
next milestone (see [PLAN.md](PLAN.md)). Windows and Linux are scoped but not started.
