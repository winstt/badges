import Foundation

/// A single mapping: "files with these extensions get this badge".
///
/// This is the atom the whole app edits and the extension reads. It is Codable so the
/// main app can write the ruleset into the shared App Group container and the
/// FinderSync extension can read it back.
struct BadgeRule: Codable, Identifiable, Equatable {
    var id: UUID
    /// Human label shown in the app, e.g. "Photoshop".
    var name: String
    /// Lower-cased file extensions this rule matches, e.g. ["psd", "psb"].
    var fileExtensions: [String]
    /// Name of the badge image. For built-in badges this is an asset name
    /// (e.g. "psdBadge"); for custom badges it is a filename in the shared container.
    var badgeAsset: String
    /// True when the badge image lives in the shared App Group container rather than
    /// the bundled asset catalog (i.e. a user-supplied / company-logo badge).
    var isCustomImage: Bool
    var isEnabled: Bool
    /// Grouping label shown as a collapsible section in the app (e.g. "Graphics",
    /// "Music", or a user-made one). The extension ignores this — it's app-side
    /// organization only.
    var category: String

    /// Fallback category for rules that don't specify one.
    static let uncategorized = "Other"

    init(
        id: UUID = UUID(),
        name: String,
        fileExtensions: [String],
        badgeAsset: String,
        isCustomImage: Bool = false,
        isEnabled: Bool = true,
        category: String = BadgeRule.uncategorized
    ) {
        self.id = id
        self.name = name
        self.fileExtensions = fileExtensions.map { $0.lowercased() }
        self.badgeAsset = badgeAsset
        self.isCustomImage = isCustomImage
        self.isEnabled = isEnabled
        self.category = category
    }

    /// Custom decoding so rules saved before categories existed (no `category` key)
    /// still load — they fall back to `uncategorized`. Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fileExtensions = try c.decode([String].self, forKey: .fileExtensions)
        badgeAsset = try c.decode(String.self, forKey: .badgeAsset)
        isCustomImage = try c.decode(Bool.self, forKey: .isCustomImage)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? BadgeRule.uncategorized
    }

    /// Does this rule apply to the given file URL?
    func matches(_ url: URL) -> Bool {
        guard isEnabled else { return false }
        return fileExtensions.contains(url.pathExtension.lowercased())
    }
}
