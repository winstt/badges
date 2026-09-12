import Cocoa
import FinderSync

/// The FinderSync extension: the part macOS actually loads to paint badges on files
/// in the Finder. Principal class referenced from the .appex Info.plist as
/// `BadgesFinderExt.FinderSync`.
///
/// Flow:
///   1. On launch we register one badge *image* per rule under a stable identifier.
///   2. Finder calls `requestBadgeIdentifier(for:)` for each visible file.
///   3. We resolve the file against the ruleset and assign the matching identifier.
///
/// Limitation baked into the platform: FinderSync draws one badge per file, in a
/// fixed corner Finder controls — we supply only the image, not its placement.
class FinderSync: FIFinderSync {

    private let controller = FIFinderSyncController.default()
    private var resolver = BadgeResolver()

    /// The shared defaults suite the app writes rule/master-switch changes into.
    /// We KVO it so toggling a badge (or the master switch) in the menu-bar UI is
    /// reflected without relaunching Finder.
    private let suite = BadgeStore.shared.suite

    override init() {
        super.init()

        // Observe the boot disk plus every mounted volume (external drives like a T7,
        // network shares, disk images). "/" alone does NOT reliably get Finder to badge
        // items on other volumes — each volume root has to be in the observed set.
        refreshObservedDirectories()

        registerBadges()

        // Cross-process KVO: the app and this extension share the App Group suite,
        // so a write in the app fires these observers here.
        suite.addObserver(self, forKeyPath: BadgeStore.rulesDefaultsKey, options: [], context: nil)
        suite.addObserver(self, forKeyPath: BadgeStore.badgingEnabledDefaultsKey, options: [], context: nil)
        suite.addObserver(self, forKeyPath: BadgeStore.fileBadgesDefaultsKey, options: [], context: nil)

        // Re-observe when drives are plugged in / ejected so a freshly mounted T7 gets
        // badged without relaunching Finder.
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didUnmountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didRenameVolumeNotification, object: nil)

        // Re-rasterize badges when the user switches Light/Dark so appearance-aware
        // art (e.g. the PNG badge: black outline in Light, white in Dark) stays legible
        // on the Finder window background. The registered badge images are static
        // bitmaps, so a theme flip needs a re-register — this observer triggers it.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    deinit {
        suite.removeObserver(self, forKeyPath: BadgeStore.rulesDefaultsKey)
        suite.removeObserver(self, forKeyPath: BadgeStore.badgingEnabledDefaultsKey)
        suite.removeObserver(self, forKeyPath: BadgeStore.fileBadgesDefaultsKey)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func appearanceChanged(_ note: Notification) {
        reload()
    }

    /// The system Light/Dark setting, resolved inside this headless extension (there's
    /// no window/NSApp appearance to inherit). Absence of the global key means Light.
    private static func systemAppearance() -> NSAppearance {
        let isDark = (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String) == "Dark"
        return NSAppearance(named: isDark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
    }

    @objc private func volumesChanged(_ note: Notification) {
        refreshObservedDirectories()
    }

    /// The set of roots Finder should ask us about: the boot volume plus every mounted
    /// volume. Building the URL list needs no file access (just paths), so it's
    /// sandbox-safe.
    private func refreshObservedDirectories() {
        var roots: Set<URL> = [URL(fileURLWithPath: "/")]
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            roots.formUnion(volumes)
        }
        controller.directoryURLs = roots
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        reload()
    }

    /// Rebuild from the current store and re-register images. Newly disabled rules
    /// stop matching on Finder's next `requestBadgeIdentifier` (fires on scroll /
    /// window refresh); newly enabled ones start matching immediately.
    private func reload() {
        resolver = BadgeResolver()
        registerBadges()
        // Re-assert the observed roots. Finder caches per-URL badge results and won't
        // re-ask on its own; dropping and re-setting the scope makes it re-query
        // `requestBadgeIdentifier` for items currently onscreen, so a toggle / manual
        // Refresh repaints the frontmost window instead of showing stale badges.
        controller.directoryURLs = []
        refreshObservedDirectories()
    }

    /// Register a Finder badge identifier for every distinct badge image.
    ///
    /// Identifiers are keyed by `badgeAsset` (not rule UUID) on purpose: asset names
    /// are stable across default re-seeding and "reset to defaults", while rule UUIDs
    /// are regenerated — a UUID-keyed registration would go stale and badges would
    /// silently stop rendering until Finder relaunches. Also dedupes registration
    /// when several rules share one image.
    private func registerBadges() {
        // Resolve the appearance once so every badge is rasterized for the current
        // Light/Dark mode (appearance-aware assets pick the right variant).
        let appearance = Self.systemAppearance()
        var registered = Set<String>()

        func register(asset: String, isCustom: Bool, label: String) {
            guard !registered.contains(asset) else { return }
            let ref = BadgeRule(name: label, fileExtensions: [], badgeAsset: asset, isCustomImage: isCustom)
            guard let image = BadgeImageLoader.image(for: ref) else {
                NSLog("Badge asset missing: \(asset)")
                return
            }
            controller.setBadgeImage(
                Self.badgeSized(image, appearance: appearance),
                label: label,
                forBadgeIdentifier: asset
            )
            registered.insert(asset)
        }

        for rule in resolver.rules {
            register(asset: rule.badgeAsset, isCustom: rule.isCustomImage, label: rule.name)
        }
    }

    /// Finder badges are small overlays; our source art is 1024px. Hand Finder a
    /// modestly-sized copy (retina-friendly) so it reliably renders the overlay
    /// instead of silently dropping an oversized image. Rasterized under `appearance`
    /// so appearance-aware art (e.g. the PNG badge) picks its Light/Dark variant.
    private static func badgeSized(_ image: NSImage, appearance: NSAppearance, side: CGFloat = 128) -> NSImage {
        let target = NSSize(width: side, height: side)
        let resized = NSImage(size: target)
        resized.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: NSRect(origin: .zero, size: target),
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0
            )
        }
        resized.unlockFocus()
        return resized
    }

    // MARK: - FIFinderSync

    /// Finder calls this for each item drawn onscreen in an observed directory. This
    /// is the only badging path that works: a sandboxed extension can't enumerate the
    /// directory itself (Finder brokers access per-URL through this callback).
    override func requestBadgeIdentifier(for url: URL) {
        guard let rule = resolver.finderSyncBadge(for: url) else { return }
        controller.setBadgeIdentifier(rule.badgeAsset, for: url)
    }
}
