# Security Policy

## Supported versions

Only the latest release of Badges receives fixes. Please update before reporting.

| Version | Supported |
|---------|-----------|
| Latest release | ✅ |
| Older releases | ❌ |

## What Badges can access

Badges is a sandboxed macOS app with a Finder Sync extension. It reads only file
**names and extensions** to choose a badge — never file contents — and makes no network
requests. Releases are signed with a Developer ID certificate and notarized by Apple.
See [PRIVACY.md](PRIVACY.md) for details.

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Instead, report them
privately through GitHub:
**[Report a vulnerability](https://github.com/winstt/badges/security/advisories/new)**.

Include the Badges and macOS versions, steps to reproduce, and what impact you think it
has. You'll get a reply within 7 days, and a fix for confirmed issues will ship in the
next release, with credit to you unless you'd rather stay anonymous.
