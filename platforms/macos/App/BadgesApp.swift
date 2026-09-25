import SwiftUI
import UserNotifications

@main
struct BadgesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // One model instance shared by the menu-bar panel and the (optional) manager
    // window, so a toggle in one is instantly reflected in the other.
    @StateObject private var model = BadgeRulesModel()

    var body: some Scene {
        // The primary UI now lives in the menu bar: the red "B" signals the app is
        // active, and its panel holds the per-badge on/off scroll. `.window` style
        // gives us a real SwiftUI view (scroll, toggles) instead of a plain NSMenu.
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            MenuBarLabel(active: model.badgingEnabled)
        }
        .menuBarExtraStyle(.window)

        // Kept for the fuller rule management coming next; opened from the panel.
        Window("Badges", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 520, minHeight: 420)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Launch-time setup checks. Both failure modes look identical to the user ("no
/// badges"), so we catch them up front instead of leaving people to wait it out.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set before launch completes so a click on a notification that relaunched us
        // is still delivered here.
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Defer one runloop turn so the menu-bar item is up before any alert shows.
        DispatchQueue.main.async {
            #if !APPSTORE
            if InstallLocation.needsMoveToApplications {
                InstallLocation.promptToMove()   // quits
                return
            }
            #endif
            ExtensionStatus.shared.promptIfDisabled()
        }
    }

    /// Show our banner even while the menu-bar panel is open (app counts as active).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking the "extension is off" notification takes the user straight to the switch.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == ExtensionStatus.notificationCategory {
            Task { @MainActor in ExtensionStatus.shared.openSettings() }
        }
        completionHandler()
    }
}

/// The menu-bar glyph: the monochrome "B" silhouette (template — it adapts to the
/// light/dark menu bar automatically). The colored red "B" lives only as the app
/// icon. Full opacity when badging is active; dimmed when the master switch is off.
private struct MenuBarLabel: View {
    let active: Bool

    var body: some View {
        if let img = NSImage(named: "MenuBarB") {
            Image(nsImage: img)
                .renderingMode(.template)
                .opacity(active ? 1 : 0.4)
        } else {
            Image(systemName: "b.square")
        }
    }
}
