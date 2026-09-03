# Badges — Linux (planned)

Linux file-manager integration for Badges. **Not built yet** — design brief.

## Reality: it's per–desktop-environment
There is no single Linux API for icon overlays. Each file manager has its own
extension mechanism, so this is N small integrations sharing one ruleset:

- **GNOME / Nautilus** — `nautilus-python` extension implementing
  `Nautilus.InfoProvider` + `add_emblem`. Emblems are the closest thing to badges.
- **KDE / Dolphin** — a `KOverlayIconPlugin` (C++/Qt) returning an overlay icon name
  per URL.
- **Cinnamon / Nemo**, **MATE / Caja** — same `*-python` InfoProvider pattern as Nautilus.

Emblems are usually named icons from the theme, so we may need to install our badge
PNGs into the user icon theme (`~/.local/share/icons/…`) and reference them by name.

## Shared contract
Same as the other platforms: read [`../../shared/rules.default.json`](../../shared)
(schema in `shared/schema/`), art from `shared/badges/`. Honour `badgingEnabled` and
per-rule `isEnabled`; match on `fileExtensions`.

## First target
GNOME/Nautilus (widest reach) + KDE/Dolphin. Package as `.deb`/`.rpm` or Flatpak;
document enabling the extension + restarting the file manager (`nautilus -q`).
