import XCTest
import AppKit

/// Exercises the custom-badge image normalization (downscale + PNG re-encode), which
/// is the riskiest new non-UI code path.
final class BadgeImageTests: XCTestCase {

    private func solidImage(_ w: Int, _ h: Int, _ color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        img.unlockFocus()
        return img
    }

    private func pixels(_ data: Data) -> (w: Int, h: Int) {
        let rep = NSBitmapImageRep(data: data)!
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    private func sourcePixels(_ img: NSImage) -> (w: Int, h: Int) {
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    func testProducesPNG() {
        let data = BadgeStore.normalizedBadgePNG(solidImage(200, 200, .red), side: 128)
        XCTAssertNotNil(data)
        // PNG magic number.
        XCTAssertEqual(Array(data!.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testClampsLongestEdgeToSide() {
        let data = BadgeStore.normalizedBadgePNG(solidImage(600, 300, .green), side: 128)!
        let px = pixels(data)
        XCTAssertLessThanOrEqual(max(px.w, px.h), 128)
    }

    func testPreservesAspectRatio() {
        let data = BadgeStore.normalizedBadgePNG(solidImage(600, 300, .green), side: 128)!
        let px = pixels(data)
        XCTAssertEqual(Double(px.w) / Double(px.h), 2.0, accuracy: 0.12,
                       "A 2:1 image should stay roughly 2:1 after scaling.")
    }

    func testNeverUpscalesSmallImage() {
        let img = solidImage(40, 40, .blue)
        let src = sourcePixels(img)
        let out = pixels(BadgeStore.normalizedBadgePNG(img, side: 1024)!)
        XCTAssertLessThanOrEqual(max(out.w, out.h), max(src.w, src.h),
                                 "Small art must not be blown up past its own pixels.")
    }
}
