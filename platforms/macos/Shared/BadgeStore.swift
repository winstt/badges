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

    /// Save already-rendered PNG data (e.g. from the in-app generator) as a custom
    /// badge. Returns the stored filename, or nil on failure.
    func saveCustomBadge(pngData: Data) -> String? {
        let filename = "gen-\(UUID().uuidString).png"
        let dest = customBadgesURL.appendingPathComponent(filename)
        do { try pngData.write(to: dest); return filename }
        catch { NSLog("saveCustomBadge failed: \(error)"); return nil }
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

    /// Which category sections the user has collapsed in the manager window. Purely UI
    /// state (the extension ignores categories), persisted so it survives relaunches.
    private let collapsedCategoriesKey = "collapsedCategories"
    var collapsedCategories: Set<String> {
        get { Set(defaults.stringArray(forKey: collapsedCategoriesKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: collapsedCategoriesKey) }
    }

    /// User-created categories that may not have any rules yet (so they'd otherwise not
    /// appear, since sections are derived from rules). Added via "+ New category".
    private let customCategoriesKey = "customCategories"
    var customCategories: [String] {
        get { defaults.stringArray(forKey: customCategoriesKey) ?? [] }
        set { defaults.set(newValue, forKey: customCategoriesKey) }
    }

    /// Set once we've run the one-time "sort existing rules into categories" migration,
    /// so it doesn't re-run and clobber a category the user deliberately set to "Other".
    private let didAutoCategorizeKey = "didAutoCategorize"
    var didAutoCategorize: Bool {
        get { defaults.bool(forKey: didAutoCategorizeKey) }
        set { defaults.set(newValue, forKey: didAutoCategorizeKey) }
    }

    // MARK: - Per-file badge overrides

    /// A badge pinned to a specific individual file (by absolute path), independent of
    /// its extension — set via the Finder right-click menu. Takes precedence over
    /// extension rules. `isCustom` says whether `asset` is a shared-container image
    /// (vs a bundled asset-catalog name), so the loader knows where to find it.
    /// `hidden` means "draw no badge at all on this file" — it suppresses even the
    /// extension/format badge (that's what "Remove badge" does).
    struct FileBadge: Codable, Equatable {
        var asset: String
        var isCustom: Bool
        var hidden: Bool

        init(asset: String, isCustom: Bool, hidden: Bool = false) {
            self.asset = asset; self.isCustom = isCustom; self.hidden = hidden
        }

        // Tolerate older entries written before `hidden` existed.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            asset = try c.decode(String.self, forKey: .asset)
            isCustom = try c.decode(Bool.self, forKey: .isCustom)
            hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        }
    }

    private let fileBadgesKey = "fileBadges"
    /// KVO key so the extension re-registers/repaints when the map changes.
    static var fileBadgesDefaultsKey: String { "fileBadges" }

    func loadFileBadges() -> [String: FileBadge] {
        guard let data = defaults.data(forKey: fileBadgesKey),
              let map = try? JSONDecoder().decode([String: FileBadge].self, from: data)
        else { return [:] }
        return map
    }

    private func saveFileBadges(_ map: [String: FileBadge]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: fileBadgesKey)
    }

    /// The per-file badge for this exact path, if any. Path-keyed, so it doesn't follow
    /// a moved/renamed file (a known limitation — bookmarks would fix it later).
    func fileBadge(for path: String) -> FileBadge? { loadFileBadges()[path] }

    /// Pin `asset` onto each of `paths` (overwrites any existing per-file badge there).
    func setFileBadge(paths: [String], asset: String, isCustom: Bool) {
        var map = loadFileBadges()
        for p in paths { map[p] = FileBadge(asset: asset, isCustom: isCustom) }
        saveFileBadges(map)
    }

    /// Mark each of `paths` as "no badge at all" — suppresses the extension/format badge
    /// too. This is "Remove badge" in the Finder menu.
    func suppressFileBadge(paths: [String]) {
        var map = loadFileBadges()
        for p in paths { map[p] = FileBadge(asset: "", isCustom: false, hidden: true) }
        saveFileBadges(map)
    }

    /// Forget any per-file setting on each of `paths` (files fall back to extension
    /// rules — i.e. show their default format badge again).
    func removeFileBadges(paths: [String]) {
        var map = loadFileBadges()
        for p in paths { map.removeValue(forKey: p) }
        saveFileBadges(map)
    }

    /// Filenames of every custom badge image in the shared container (generated or
    /// uploaded). Used to offer them as per-file badge choices in the Finder menu.
    func customBadgeFilenames() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: customBadgesURL, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { $0.lastPathComponent }
            .sorted()
    }
}

extension BadgeRule {
    /// The badges that ship in the box, grouped into categories. Order here = priority
    /// (top wins) and also the initial category order.
    static var builtInDefaults: [BadgeRule] {
        [
            // Graphics (Adobe suite / design)
            BadgeRule(name: "Photoshop", fileExtensions: ["psd", "psb"], badgeAsset: "psdBadge", category: "Graphics"),
            BadgeRule(name: "Illustrator", fileExtensions: ["ai"], badgeAsset: "aiBadge", category: "Graphics"),
            BadgeRule(name: "After Effects", fileExtensions: ["aep"], badgeAsset: "aepBadge", category: "Graphics"),
            BadgeRule(name: "Premiere", fileExtensions: ["prproj"], badgeAsset: "prprojBadge", category: "Graphics"),
            BadgeRule(name: "PDF", fileExtensions: ["pdf"], badgeAsset: "pdfBadge", category: "Graphics"),
            BadgeRule(name: "SVG", fileExtensions: ["svg"], badgeAsset: "svgBadge", category: "Graphics"),
            // Music (audio / producers)
            BadgeRule(name: "MP3", fileExtensions: ["mp3"], badgeAsset: "mp3Badge", category: "Music"),
            BadgeRule(name: "WAV", fileExtensions: ["wav"], badgeAsset: "wavBadge", category: "Music"),
            BadgeRule(name: "FL Studio", fileExtensions: ["flp"], badgeAsset: "flpBadge", category: "Music"),
            // Video
            BadgeRule(name: "MP4", fileExtensions: ["mp4"], badgeAsset: "mp4Badge", category: "Video"),
            BadgeRule(name: "MKV", fileExtensions: ["mkv"], badgeAsset: "mkvBadge", category: "Video"),
            BadgeRule(name: "MOV", fileExtensions: ["mov"], badgeAsset: "movBadge", category: "Video"),
            // Images
            BadgeRule(name: "PNG", fileExtensions: ["png"], badgeAsset: "pngBadge", category: "Images"),
            BadgeRule(name: "HEIC", fileExtensions: ["heic"], badgeAsset: "heicBadge", category: "Images"),
            // 3D
            BadgeRule(name: "Blender", fileExtensions: ["blend"], badgeAsset: "blendBadge", category: "3D"),
        ]
    }

    /// Bundled badge asset names, for the badge picker in the editor.
    static let bundledBadgeAssets = [
        "psdBadge", "aiBadge", "aepBadge", "prprojBadge", "pdfBadge", "svgBadge",
        "mp3Badge", "wavBadge", "flpBadge",
        "mp4Badge", "mkvBadge", "movBadge",
        "pngBadge", "heicBadge", "blendBadge",
    ]
}
