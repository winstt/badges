import SwiftUI

extension Image {
    /// Build a SwiftUI `Image` from an `NSImage` in a way that actually honors
    /// `.interpolation(.high)`.
    ///
    /// On macOS, `Image(nsImage:).interpolation(.high)` is unreliable — SwiftUI often
    /// ignores the interpolation quality for NSImage-backed images and downsamples our
    /// 1024px badge art with a low-quality filter, so previews look jagged/pixelated at
    /// small sizes. Wrapping the underlying `CGImage` via `Image(decorative:scale:)`
    /// makes the interpolation modifier take effect, giving crisp downscaled previews.
    init(badge nsImage: NSImage) {
        if let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.init(decorative: cg, scale: 1)
        } else {
            self.init(nsImage: nsImage)
        }
    }
}
