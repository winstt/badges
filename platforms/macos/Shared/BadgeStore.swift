import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Why a custom badge image couldn't be imported — surfaced to the user in the editor.
enum BadgeImportError: LocalizedError {
    case tooLarge(mb: Double, maxMB: Double)
    case unreadable

    var errorDescription: String? {
        switch self {
        case let .tooLarge(mb, maxMB):
            return String(format: "That image is %.1f MB — the limit is %.0f MB.", mb, maxMB)
        case .unreadable:
            return "That file isn't a readable image."
        }
    }
}

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

    /// Largest source image we'll accept (before normalizing).
    static let maxBadgeImageMB: Double = 5
    /// Badge art is stored square-ish at this longest edge; the extension downscales
    /// again to ~128px at registration. 1024 keeps it crisp on Retina without bloat.
    static let badgeStorageSide: CGFloat = 1024

    /// Copy a user-picked image into the shared container as a normalized PNG so both
    /// the app and the extension can load it as a custom badge. Returns the stored
    /// filename (to put in `BadgeRule.badgeAsset` with `isCustomImage = true`).
    ///
    /// Throws `BadgeImportError` for oversized or unreadable input. Large images are
    /// downscaled to `badgeStorageSide`; small ones are kept as-is. Always re-encoded
    /// to PNG (consistent format + alpha), so the on-disk name always ends `.png`.
    func importCustomBadge(from source: URL) throws -> String {
        // The URL comes from a sandbox open-panel; access is security-scoped.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let attrs = try? FileManager.default.attributesOfItem(atPath: source.path)
        if let bytes = attrs?[.size] as? Int {
            let mb = Double(bytes) / 1_048_576
            if mb > Self.maxBadgeImageMB {
                throw BadgeImportError.tooLarge(mb: mb, maxMB: Self.maxBadgeImageMB)
            }
        }

        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: source),
              let png = Self.normalizedBadgePNG(image, side: Self.badgeStorageSide)
        else { throw BadgeImportError.unreadable }
        #else
        let png = try Data(contentsOf: source)
        #endif

        let filename = "custom-\(UUID().uuidString).png"
        let dest = customBadgesURL.appendingPathComponent(filename)
        do {
            try png.write(to: dest)
            return filename
        } catch {
            NSLog("importCustomBadge write failed: \(error)")
            throw BadgeImportError.unreadable
        }
    }

    #if canImport(AppKit)
    /// Redraw an image at no more than `side` on its longest edge (never upscales) and
    /// encode as PNG with alpha. Returns nil if the image has no usable bitmap.
    static func normalizedBadgePNG(_ image: NSImage, side: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, side / max(w, h))
        let tw = max(1, Int((w * scale).rounded()))
        let th = max(1, Int((h * scale).rounded()))
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        out.size = NSSize(width: tw, height: th)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: tw, height: th),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .png, properties: [:])
    }
    #endif

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
