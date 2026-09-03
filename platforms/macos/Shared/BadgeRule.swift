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

    init(
        id: UUID = UUID(),
        name: String,
        fileExtensions: [String],
        badgeAsset: String,
        isCustomImage: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.fileExtensions = fileExtensions.map { $0.lowercased() }
        self.badgeAsset = badgeAsset
        self.isCustomImage = isCustomImage
        self.isEnabled = isEnabled
    }

    /// Does this rule apply to the given file URL?
    func matches(_ url: URL) -> Bool {
        guard isEnabled else { return false }
        return fileExtensions.contains(url.pathExtension.lowercased())
    }
}
