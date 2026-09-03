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

        // Re-observe when drives are plugged in / ejected so a freshly mounted T7 gets
        // badged without relaunching Finder.
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didUnmountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didRenameVolumeNotification, object: nil)
    }

    deinit {
        suite.removeObserver(self, forKeyPath: BadgeStore.rulesDefaultsKey)
        suite.removeObserver(self, forKeyPath: BadgeStore.badgingEnabledDefaultsKey)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
        var registered = Set<String>()
        for rule in resolver.rules where !registered.contains(rule.badgeAsset) {
            guard let image = BadgeImageLoader.image(for: rule) else {
                NSLog("Badge asset missing: \(rule.badgeAsset)")
                continue
            }
            controller.setBadgeImage(
                Self.badgeSized(image),
                label: rule.name,
                forBadgeIdentifier: rule.badgeAsset
            )
            registered.insert(rule.badgeAsset)
        }
    }

    /// Finder badges are small overlays; our source art is 1024px. Hand Finder a
    /// modestly-sized copy (retina-friendly) so it reliably renders the overlay
    /// instead of silently dropping an oversized image.
    private static func badgeSized(_ image: NSImage, side: CGFloat = 128) -> NSImage {
        let target = NSSize(width: side, height: side)
        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
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
