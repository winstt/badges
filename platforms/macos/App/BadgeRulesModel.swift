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
        // Clean up an orphaned custom image if no other rule still uses it.
        if rule.isCustomImage, !rules.contains(where: { $0.badgeAsset == rule.badgeAsset }) {
            store.deleteCustomBadge(named: rule.badgeAsset)
        }
    }

    func addRule(_ rule: BadgeRule) {
        rules.append(rule)
    }

    /// Copy a user-picked PNG into the shared container. Returns the stored filename
    /// to use as a custom `badgeAsset`.
    func importCustomBadge(from url: URL) -> String? {
        store.importCustomBadge(from: url)
    }

    /// Extensions already claimed by another rule — used to warn about duplicates.
    func conflictingExtensions(_ exts: [String], excluding ruleID: UUID? = nil) -> [String] {
        let taken = Set(rules.filter { $0.id != ruleID }.flatMap { $0.fileExtensions })
        return exts.filter { taken.contains($0) }
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
