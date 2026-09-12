import AppKit

/// Adobe Creative Cloud ships a Finder Sync extension ("Core Sync",
/// `com.adobe.accmac.ACCFinderSync`) that monopolizes the single per-file badge slot —
/// while it's enabled, Finder never asks us to badge files, so Badges appears to do
/// nothing. This is our audience's most common "no badges" cause.
///
/// macOS security does **not** let one sandboxed app silently disable another vendor's
/// Finder extension (that toggle lives behind the user's own click in System Settings).
/// So the flow is: detect Adobe, explain the conflict, and deep-link the user straight
/// to the pane where they flip it off.
enum AdobeConflict {

    /// Presence of any of these means Adobe Creative Cloud — and almost certainly its
    /// Core Sync Finder extension — is installed.
    private static let adobeBundleIDs = [
        "com.adobe.acc.AdobeCreativeCloud",
        "com.adobe.CreativeCloud",
        "com.adobe.Photoshop",
        "com.adobe.illustrator",
        "com.adobe.AfterEffects",
        "com.adobe.PremierePro",
        "com.adobe.Acrobat.Pro",
        "com.adobe.Bridge",
        "com.adobe.Audition",
        "com.adobe.InDesign",
    ]

    /// True if any known Adobe app is installed. Uses LaunchServices (sandbox-safe);
    /// we can't read whether the extension is *enabled* from inside the sandbox, so we
    /// key off "Adobe is here" and let the user confirm/toggle.
    static func adobeInstalled() -> Bool {
        let ws = NSWorkspace.shared
        return adobeBundleIDs.contains { ws.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// Open System Settings at the pane that lists Finder extensions so the user can
    /// turn off Adobe "Core Sync". Pane identifiers changed across macOS versions, so
    /// try the newest first and fall back.
    static func openExtensionSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension", // Ventura+
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.preferences.extensions",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
