# Badges — Windows (planned)

Windows shell integration for Badges. **Not built yet** — this is the design brief.

## Approach
File Explorer badges = an **icon overlay handler** implementing
[`IShellIconOverlayIdentifier`](https://learn.microsoft.com/windows/win32/api/shobjidl_core/nn-shobjidl_core-ishelliconoverlayidentifier),
registered as an in-process COM server (a DLL). Explorer loads it and asks, per
file, whether to composite an overlay onto the icon.

Candidate stacks:
- **C# / .NET** with [SharpShell](https://github.com/dwmkerr/sharpshell) — fastest to prototype.
- **Rust** (`windows` crate) or **C++** — leaner DLL, no .NET runtime dependency.

## Hard constraints (design around these early)
- **~15 overlay-handler slots system-wide**, shared across all apps and sorted
  **alphabetically** by registry key name. Dropbox / OneDrive / TortoiseGit already
  squat the top slots — the exact "contested slot" problem we hit with Adobe on macOS.
  Mitigation: register keys with a leading space / `!` so we sort first, and document it.
- One overlay per file (like FinderSync). No placement control.
- Handler must be fast and must not block Explorer.

## Shared contract
Read the ruleset from [`../../shared/rules.default.json`](../../shared) (schema in
`shared/schema/rules.schema.json`). Badge art = `shared/badges/*.png`, downscaled to
the overlay size Explorer expects (typically 16–256px per DPI). Match `fileExtensions`,
honour `badgingEnabled` and per-rule `isEnabled`.

## Open questions
- Config UI: reuse a cross-platform shell (Tauri/WinUI) or a minimal tray app.
- Installer: MSI / MSIX; overlay handlers need registry registration + Explorer restart.
