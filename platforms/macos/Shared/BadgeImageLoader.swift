import Foundation
#if canImport(AppKit)
import AppKit

/// Loads a badge's image whether it's a bundled asset or a user-supplied custom file
/// in the shared container. Used by FinderSync badge registration and the app's UI.
enum BadgeImageLoader {
    static func image(for rule: BadgeRule) -> NSImage? {
        if rule.isCustomImage {
            let url = BadgeStore.shared.customBadgesURL
                .appendingPathComponent(rule.badgeAsset)
            return NSImage(contentsOf: url)
        }
        // Bundled asset catalog image. Works from within whichever bundle
        // (extension or app) this code is compiled into.
        return NSImage(named: rule.badgeAsset)
    }
}
#endif
