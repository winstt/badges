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

    /// Collapsed category sections in the manager window (persisted, app-only UI state).
    @Published var collapsedCategories: Set<String> {
        didSet { store.collapsedCategories = collapsedCategories }
    }

    /// User-made categories that may not have rules yet (so they still show as sections).
    @Published var customCategories: [String] {
        didSet { store.customCategories = customCategories }
    }

    private let store: BadgeStore

    init(store: BadgeStore = .shared) {
        self.store = store
        self.rules = store.loadRules()
        self.badgingEnabled = store.badgingEnabled
        self.collapsedCategories = store.collapsedCategories
        self.customCategories = store.customCategories

        // One-time migration: rules created before categories existed decode as "Other".
        // Sort them into known categories once (never touches deliberately-set ones after).
        if !store.didAutoCategorize {
            applyAutoCategorize()
            store.saveRules(rules)   // observers don't fire during init, so persist by hand
            store.didAutoCategorize = true
        }
    }

    /// Extension → category map used by auto-categorize.
    private static let categoryByExtension: [String: String] = {
        var m = [String: String]()
        func add(_ category: String, _ exts: [String]) { exts.forEach { m[$0] = category } }
        add("Graphics", ["psd", "psb", "ai", "aep", "prproj", "pdf", "svg", "indd", "eps", "sketch", "fig", "xd", "afphoto", "afdesign"])
        add("Music", ["mp3", "wav", "flp", "aiff", "aif", "als", "logicx", "m4a", "flac", "aac", "ogg", "mid", "midi"])
        add("Video", ["mp4", "mkv", "mov", "avi", "wmv", "webm", "m4v"])
        add("Images", ["png", "heic", "jpg", "jpeg", "gif", "tiff", "tif", "webp", "bmp", "heif"])
        add("3D", ["blend", "obj", "fbx", "stl", "c4d", "gltf", "glb"])
        return m
    }()

    /// Assign a category to any rule still in "Other" whose extension we recognise.
    private func applyAutoCategorize() {
        for i in rules.indices where rules[i].category == BadgeRule.uncategorized {
            if let ext = rules[i].fileExtensions.first(where: { Self.categoryByExtension[$0] != nil }),
               let cat = Self.categoryByExtension[ext] {
                rules[i].category = cat
            }
        }
    }

    /// Button-triggered version (mutations here fire the save via didSet).
    func autoCategorize() { applyAutoCategorize() }

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

    /// New rules join the top of their own category (highest priority within it). A
    /// brand-new category is shown first.
    func addRule(_ rule: BadgeRule) {
        if let firstInCategory = rules.firstIndex(where: { $0.category == rule.category }) {
            rules.insert(rule, at: firstInCategory)
        } else {
            rules.insert(rule, at: 0)
        }
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

    // MARK: Categories

    /// The canonical category order sections are shown in. Anything else (e.g. "Other"
    /// or a user-made category) follows, in the order it first appears.
    static let preferredCategoryOrder = ["Graphics", "Images", "Video", "Music", "3D"]

    /// Categories to show as sections: those used by rules plus any empty user-made
    /// ones, sorted into `preferredCategoryOrder` with the rest appended.
    var orderedCategories: [String] {
        var seen = Set<String>()
        var cats: [String] = []
        for rule in rules where seen.insert(rule.category).inserted { cats.append(rule.category) }
        for c in customCategories where seen.insert(c).inserted { cats.append(c) }
        return cats.enumerated().sorted { lhs, rhs in
            let rank = { (name: String, appearance: Int) -> Int in
                Self.preferredCategoryOrder.firstIndex(of: name)
                    ?? (Self.preferredCategoryOrder.count + appearance)
            }
            return rank(lhs.element, lhs.offset) < rank(rhs.element, rhs.offset)
        }.map { $0.element }
    }

    /// Create an empty category (from "+ New category"); it shows as a section you can
    /// then drop rules into. No-op for blank or already-existing names.
    func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !orderedCategories.contains(trimmed) else { return }
        customCategories.append(trimmed)
    }

    /// Remove a category. No badges are deleted — any rules in it move to "Other" (so
    /// they stay visible and can be re-categorized). Also drops it from the user-made
    /// and collapsed sets.
    func removeCategory(_ name: String) {
        guard name != BadgeRule.uncategorized else { return }
        if rules.contains(where: { $0.category == name }) {
            var updated = rules
            for i in updated.indices where updated[i].category == name {
                updated[i].category = BadgeRule.uncategorized
            }
            rules = updated   // one save instead of one per rule
        }
        customCategories.removeAll { $0 == name }
        collapsedCategories.remove(name)
    }

    /// Number of badges in a category — used to warn before removing a non-empty one.
    func ruleCount(in category: String) -> Int { rules(in: category).count }

    /// Rules in one category, preserving their global (priority) order.
    func rules(in category: String) -> [BadgeRule] {
        rules.filter { $0.category == category }
    }

    func isCollapsed(_ category: String) -> Bool { collapsedCategories.contains(category) }

    func toggleCollapsed(_ category: String) {
        if collapsedCategories.contains(category) { collapsedCategories.remove(category) }
        else { collapsedCategories.insert(category) }
    }

    // MARK: Priority (list order = priority; index 0 wins). Reorder is within-category.

    /// Drag-to-reorder hook for the List.
    func move(fromOffsets: IndexSet, toOffset: Int) {
        rules.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    /// Move a rule up within its own category (above its previous same-category sibling).
    func promote(_ rule: BadgeRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }),
              let j = stride(from: i - 1, through: 0, by: -1)
                .first(where: { rules[$0].category == rule.category })
        else { return }
        let r = rules.remove(at: i)
        rules.insert(r, at: j)
    }

    /// Move a rule down within its own category (below its next same-category sibling).
    func demote(_ rule: BadgeRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }),
              let j = ((i + 1)..<rules.count)
                .first(where: { rules[$0].category == rule.category })
        else { return }
        let r = rules.remove(at: i)
        rules.insert(r, at: j)  // after removal the sibling shifted to j-1, so this lands after it
    }

    /// True when the rule is the first/last in its category (to disable up/down).
    func isFirstInCategory(_ rule: BadgeRule) -> Bool {
        rules(in: rule.category).first?.id == rule.id
    }
    func isLastInCategory(_ rule: BadgeRule) -> Bool {
        rules(in: rule.category).last?.id == rule.id
    }

    /// Copy a user-picked image into the shared container (normalized PNG). Throws
    /// `BadgeImportError`. Returns the stored filename to use as a custom `badgeAsset`.
    func importCustomBadge(from url: URL) throws -> String {
        try store.importCustomBadge(from: url)
    }

    /// Save a generated badge PNG as a custom badge; returns its filename.
    func saveCustomBadge(pngData: Data) -> String? {
        store.saveCustomBadge(pngData: pngData)
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
