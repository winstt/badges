import AppKit
import Combine
import FinderSync
import UserNotifications

// MARK: - Install location

// Direct-download (DMG) builds only. Mac App Store installs always land in
// /Applications and are never translocated, and the lookup below uses a Security
// symbol that isn't in the public headers — so it stays out of the App Store build.
#if !APPSTORE
/// Where the running copy of Badges lives. Launching straight from the downloaded
/// `.dmg` makes macOS run it via App Translocation (a random read-only copy under
/// `…/AppTranslocation/…`). From there the FinderSync extension never gets
/// registered — it doesn't even show up in System Settings — so badges silently
/// never appear until the user happens to launch the copy in /Applications.
/// Verified in a clean Sequoia VM: DMG launch → `pluginkit` has no match at all;
/// same build launched from /Applications → extension runs within a second.
enum InstallLocation {
    /// True when this copy can't host a working extension: translocated, or running
    /// from a read-only volume (the mounted disk image).
    static var needsMoveToApplications: Bool {
        let url = Bundle.main.bundleURL
        if url.path.contains("/AppTranslocation/") { return true }
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly
        return readOnly == true
    }

    /// The app as the user sees it (inside the mounted DMG), so we can point Finder at
    /// it. For a translocated launch that's the original path, not the random copy.
    static var originalBundleURL: URL {
        let url = Bundle.main.bundleURL
        return untranslocatedURL(url) ?? url
    }

    /// Resolve a translocated URL back to its original via Security's
    /// `SecTranslocateCreateOriginalPathForURL` (exported but not in the public headers,
    /// hence the dlsym). Returns nil if unavailable or not translocated.
    private static func untranslocatedURL(_ url: URL) -> URL? {
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    /// Explain the problem and open the two Finder windows the user needs — the DMG with
    /// Badges selected, and /Applications — then quit. A sandboxed app can't copy itself
    /// into /Applications, so the drag has to be the user's.
    @MainActor
    static func promptToMove() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move Badges to your Applications folder"
        alert.informativeText = """
            Badges is running from the downloaded disk image, so macOS won't load its \
            Finder extension and no badges will appear.

            Drag Badges into Applications, eject the disk image, and open Badges from \
            Applications.
            """
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
            NSWorkspace.shared.activateFileViewerSelecting([originalBundleURL])
        }
        NSApp.terminate(nil)
    }
}
#endif

// MARK: - Extension status

/// Whether the user has switched on the Finder extension in System Settings. macOS
/// installs FinderSync extensions *off*; until the user flips the switch nothing is
/// badged and nothing tells them why. Polled because there's no change notification.
/// A sandboxed app can't enable it for the user, so we point them at the switch:
/// launch alert, menu-bar banner, and a system notification if it goes off later.
@MainActor
final class ExtensionStatus: ObservableObject {
    static let shared = ExtensionStatus()

    @Published private(set) var isEnabled = FIFinderSyncController.isExtensionEnabled

    private var timer: Timer?

    private init() {
        // Cheap (a pluginkit lookup), and it lets the "turn it on" banner disappear the
        // moment the user flips the switch in System Settings.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in ExtensionStatus.shared.refresh() }
        }
    }

    func refresh() {
        let now = FIFinderSyncController.isExtensionEnabled
        guard now != isEnabled else { return }
        isEnabled = now
        if now {
            reminder?.invalidate()
            reminder = nil
        } else {
            // Switched off while we're running (by the user, a macOS update, or another
            // extension taking over) — badges just vanished, so say why.
            notifyDisabled()
        }
    }

    // MARK: Notifications

    nonisolated static let notificationCategory = "extensionOff"
    private static let reminderDelay: TimeInterval = 10 * 60
    private var reminder: Timer?

    /// After "Later" on the launch alert: nudge once more if it's still off in a while.
    private func scheduleReminder() {
        reminder?.invalidate()
        reminder = Timer.scheduledTimer(withTimeInterval: Self.reminderDelay, repeats: false) { _ in
            Task { @MainActor in
                let status = ExtensionStatus.shared
                status.reminder = nil
                status.refresh()
                if !status.isEnabled { status.notifyDisabled() }
            }
        }
    }

    /// Post "extension is off" as a system notification. Clicking it opens System
    /// Settings (handled in AppDelegate). Silently skipped if the user denied
    /// notifications — the menu-bar banner still covers it.
    func notifyDisabled() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Badges Finder extension is off"
            content.body = "Badges can't appear in Finder. Click to turn it on in System Settings."
            content.categoryIdentifier = Self.notificationCategory
            // Fixed identifier: a repeat replaces the old one instead of stacking up.
            let request = UNNotificationRequest(identifier: Self.notificationCategory,
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Opens System Settings → Login Items & Extensions → Finder.
    func openSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// First-launch nudge: a one-off alert if the extension is off. The menu-bar panel
    /// keeps showing a banner afterwards, so "Later" isn't a dead end.
    func promptIfDisabled() {
        refresh()
        guard !isEnabled else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Turn on the Badges Finder extension"
        alert.informativeText = """
            Badges draws its badges through a Finder extension, which macOS installs \
            switched off.

            In System Settings → General → Login Items & Extensions → Finder, turn on \
            Badges. Badges appear right away.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        } else {
            scheduleReminder()
        }
    }
}
