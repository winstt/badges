import Foundation

/// The shared source of truth for the badge ruleset.
///
/// Both the main app (which edits rules) and the extensions (which read them) talk to
/// the same App Group container, so a change in the UI is visible to Finder without
/// any custom IPC. Keep `appGroupID` in sync with the App Group entitlement configured
/// on *every* target (see project.yml).
///
/// All stored properties are immutable after init and UserDefaults is thread-safe,
/// hence the @unchecked Sendable.
final class BadgeStore: @unchecked Sendable {
    /// macOS Developer ID apps must use *Team-ID-prefixed* app groups
    /// (`<TeamID>.name`), not the iOS-style `group.*` — the latter needs a
    /// provisioning profile and triggers a consent prompt on macOS 15+.
    /// Matches `$(TeamIdentifierPrefix)com.matyasnowak.badges` in project.yml.
    /// TEAMID = ATQ3U47NSK (Apple Developer Team ID, from the signing cert's OU).
    static let appGroupID = "ATQ3U47NSK.com.matyasnowak.badges"

    /// Single shared instance. The extensions are short-lived processes, so they build
    /// one of these on launch and read once.
    static let shared = BadgeStore()

    private let defaults: UserDefaults
    private let rulesKey = "badgeRules"
    private let badgingEnabledKey = "badgingEnabled"

    /// The store's UserDefaults suite. Exposed so the extension can observe it
    /// (KVO) and pick up ruleset / master-switch changes made by the app.
    var suite: UserDefaults { defaults }
    static var rulesDefaultsKey: String { "badgeRules" }
    static var badgingEnabledDefaultsKey: String { "badgingEnabled" }

    /// Directory in the shared container where custom (user/company) badge images live.
    let customBadgesURL: URL

    private init() {
        // Fall back to standard defaults if the App Group isn't wired up yet, so the
        // code still runs during early bring-up instead of crashing.
        self.defaults = UserDefaults(suiteName: BadgeStore.appGroupID) ?? .standard

        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BadgeStore.appGroupID)
        #if DEBUG
        if container == nil {
            NSLog("BadgeStore: App Group container missing — replace TEAMID in appGroupID and check the entitlements on this target")
        }
        #endif
        let base = container ?? FileManager.default.temporaryDirectory
        self.customBadgesURL = base.appendingPathComponent("CustomBadges", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: customBadgesURL, withIntermediateDirectories: true
        )
    }

    /// Load the current ruleset, seeding the built-in defaults on first launch.
    func loadRules() -> [BadgeRule] {
        guard let data = defaults.data(forKey: rulesKey),
              let rules = try? JSONDecoder().decode([BadgeRule].self, from: data)
        else {
            let seeded = BadgeRule.builtInDefaults
            saveRules(seeded)
            return seeded
        }
        return rules
    }

    func saveRules(_ rules: [BadgeRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: rulesKey)
    }

    /// Copy a user-picked image into the shared container so both the app and the
    /// extension can load it as a custom badge. Returns the stored filename (to put in
    /// `BadgeRule.badgeAsset` with `isCustomImage = true`), or nil on failure.
    func importCustomBadge(from source: URL) -> String? {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let filename = "custom-\(UUID().uuidString).\(ext)"
        let dest = customBadgesURL.appendingPathComponent(filename)
        // The URL comes from a sandbox open-panel; access is security-scoped.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: source)
            try data.write(to: dest)
            return filename
        } catch {
            NSLog("importCustomBadge failed: \(error)")
            return nil
        }
    }

    /// Remove a custom badge file no rule references anymore. No-op for bundled assets.
    func deleteCustomBadge(named filename: String) {
        let url = customBadgesURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Master switch. When off, the extension draws no badges at all — the menu-bar
    /// "B" dims to signal the paused state. Defaults to on.
    var badgingEnabled: Bool {
        get {
            // Absent key = first run = on.
            defaults.object(forKey: badgingEnabledKey) as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: badgingEnabledKey) }
    }
}

extension BadgeRule {
    /// The badges that ship in the box (psd, ai, pdf, svg, mp4, blend) — the original
    /// set, all with artwork in BadgeAssets.xcassets.
    static var builtInDefaults: [BadgeRule] {
        [
            BadgeRule(name: "Photoshop", fileExtensions: ["psd", "psb"], badgeAsset: "psdBadge"),
            BadgeRule(name: "Illustrator", fileExtensions: ["ai"], badgeAsset: "aiBadge"),
            BadgeRule(name: "PDF", fileExtensions: ["pdf"], badgeAsset: "pdfBadge"),
            BadgeRule(name: "SVG", fileExtensions: ["svg"], badgeAsset: "svgBadge"),
            BadgeRule(name: "MP4", fileExtensions: ["mp4"], badgeAsset: "mp4Badge"),
            BadgeRule(name: "Blender", fileExtensions: ["blend"], badgeAsset: "blendBadge"),
        ]
    }

    /// Bundled badge asset names, for the "Add format" picker.
    static let bundledBadgeAssets = [
        "psdBadge", "aiBadge", "pdfBadge", "svgBadge", "mp4Badge", "blendBadge",
    ]
}
