import SwiftUI
import Combine

/// The app-side view model. Owns the editable ruleset and writes every change straight
/// back to the shared store so the Finder extension picks it up. Keeping persistence
/// eager (save on mutate) means there's no "apply" button to forget.
@MainActor
final class BadgeRulesModel: ObservableObject {
    @Published var rules: [BadgeRule] {
        didSet { store.saveRules(rules) }
    }

    /// Master switch mirrored into the shared store so the extension (and the
    /// menu-bar "B") reflect the paused/active state.
    @Published var badgingEnabled: Bool {
        didSet { store.badgingEnabled = badgingEnabled }
    }

    private let store: BadgeStore

    init(store: BadgeStore = .shared) {
        self.store = store
        self.rules = store.loadRules()
        self.badgingEnabled = store.badgingEnabled
    }

    /// Count of rules currently drawing badges — shown in the menu-bar header.
    var enabledCount: Int { rules.filter { $0.isEnabled }.count }

    func toggle(_ rule: BadgeRule) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx].isEnabled.toggle()
    }

    func delete(_ rule: BadgeRule) {
        rules.removeAll { $0.id == rule.id }
    }

    func addRule(_ rule: BadgeRule) {
        rules.append(rule)
    }

    func resetToDefaults() {
        rules = BadgeRule.builtInDefaults
    }

    /// Ask Finder to repaint badges. Re-saving the ruleset bumps the shared key the
    /// extension observes, which makes it re-register images and re-assert its
    /// observed roots — forcing Finder to re-query badges for visible items (clears
    /// stale "no badge" results in the frontmost window).
    func refresh() {
        store.saveRules(rules)
    }
}
