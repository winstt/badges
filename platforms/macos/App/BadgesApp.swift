import SwiftUI

@main
struct BadgesApp: App {
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
