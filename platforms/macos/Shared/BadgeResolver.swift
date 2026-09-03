import Foundation

/// Turns "here is a file URL" into "here are the badges to draw" for the FinderSync
/// extension.
struct BadgeResolver {
    let rules: [BadgeRule]
    /// Master switch — when off, nothing matches regardless of per-rule state.
    let badgingEnabled: Bool

    init(store: BadgeStore = .shared) {
        self.rules = store.loadRules()
        self.badgingEnabled = store.badgingEnabled
    }

    init(rules: [BadgeRule], badgingEnabled: Bool = true) {
        self.rules = rules
        self.badgingEnabled = badgingEnabled
    }

    /// All badges matching this file.
    func badges(for url: URL) -> [BadgeRule] {
        guard badgingEnabled else { return [] }
        return rules.filter { $0.matches(url) }
    }

    /// The single badge FinderSync draws for this file — the first matching rule.
    /// (Finder shows only one badge per file, in a fixed corner it controls.)
    func finderSyncBadge(for url: URL) -> BadgeRule? {
        badges(for: url).first
    }
}
