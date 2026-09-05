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
        garbageCollect(customBadge: rule.isCustomImage ? rule.badgeAsset : nil)
    }

    /// New rules land at the top so a just-added, more-specific rule out-prioritises
    /// the general ones already there (priority = list order, top wins).
    func addRule(_ rule: BadgeRule) {
        rules.insert(rule, at: 0)
    }

    /// Replace an existing rule in place (create+edit share one editor). If the edit
    /// swapped out a custom image, GC the old file when nothing else references it.
    func update(_ rule: BadgeRule) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let old = rules[idx]
        rules[idx] = rule
        if old.isCustomImage, old.badgeAsset != rule.badgeAsset {
            garbageCollect(customBadge: old.badgeAsset)
        }
    }

    // MARK: Priority (list order = priority; index 0 wins)

    /// Drag-to-reorder hook for the List.
    func move(fromOffsets: IndexSet, toOffset: Int) {
        rules.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func promote(_ rule: BadgeRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }), i > 0 else { return }
        rules.swapAt(i, i - 1)
    }

    func demote(_ rule: BadgeRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }), i < rules.count - 1 else { return }
        rules.swapAt(i, i + 1)
    }

    /// Copy a user-picked image into the shared container (normalized PNG). Throws
    /// `BadgeImportError`. Returns the stored filename to use as a custom `badgeAsset`.
    func importCustomBadge(from url: URL) throws -> String {
        try store.importCustomBadge(from: url)
    }

    /// Delete a custom badge file if no rule still references it.
    private func garbageCollect(customBadge filename: String?) {
        guard let filename, !rules.contains(where: { $0.badgeAsset == filename }) else { return }
        store.deleteCustomBadge(named: filename)
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
