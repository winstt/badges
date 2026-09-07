import AppKit

/// Renders an on-brand badge in the house style: a document shape (rounded corners +
/// a chamfered top-right fold) filled with a chosen colour, a big app glyph, and the
/// file extension as a label underneath — the same look as the bundled AEP/PSD art.
enum BadgeGenerator {

    static func makePNG(glyph: String, label: String, color: NSColor, side: CGFloat = 1024) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high

        let bg = color.usingColorSpace(.deviceRGB) ?? color
        let glyphTint = bg.blended(withFraction: 0.60, of: .white) ?? .white
        let fold = bg.blended(withFraction: 0.30, of: .white) ?? bg

        let pad = side * 0.09
        let rect = NSRect(x: pad, y: pad, width: side - 2 * pad, height: side - 2 * pad)
        let radius = side * 0.09
        let chamfer = rect.width * 0.26

        let path = documentPath(rect: rect, radius: radius, chamfer: chamfer)
        bg.setFill(); path.fill()

        // The folded page corner (a lighter triangle in the chamfer).
        let foldPath = NSBezierPath()
        foldPath.move(to: NSPoint(x: rect.maxX - chamfer, y: rect.maxY))
        foldPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY - chamfer))
        foldPath.line(to: NSPoint(x: rect.maxX - chamfer, y: rect.maxY - chamfer))
        foldPath.close()
        fold.setFill(); foldPath.fill()

        drawText(glyph, in: rect, weight: .bold, sizeFactor: 0.40, color: glyphTint, yFraction: 0.58)
        drawText(label.uppercased(), in: rect, weight: .heavy, sizeFactor: 0.17, color: .white, yFraction: 0.22)

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func makeImage(glyph: String, label: String, color: NSColor, side: CGFloat = 256) -> NSImage? {
        guard let data = makePNG(glyph: glyph, label: label, color: color, side: side) else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Shape

    /// Document outline: rounded top-left / bottom-left / bottom-right corners and a
    /// straight chamfer across the top-right (the "folded corner").
    private static func documentPath(rect: NSRect, radius: CGFloat, chamfer: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        p.line(to: NSPoint(x: rect.maxX - chamfer, y: rect.maxY))          // top edge
        p.line(to: NSPoint(x: rect.maxX, y: rect.maxY - chamfer))          // chamfer cut
        p.appendArc(from: NSPoint(x: rect.maxX, y: rect.minY),
                    to: NSPoint(x: rect.minX, y: rect.minY), radius: radius) // right + BR
        p.appendArc(from: NSPoint(x: rect.minX, y: rect.minY),
                    to: NSPoint(x: rect.minX, y: rect.maxY), radius: radius) // bottom + BL
        p.appendArc(from: NSPoint(x: rect.minX, y: rect.maxY),
                    to: NSPoint(x: rect.maxX, y: rect.maxY), radius: radius) // left + TL
        p.close()
        return p
    }

    // MARK: - Text

    private static func drawText(_ string: String, in rect: NSRect, weight: NSFont.Weight,
                                 sizeFactor: CGFloat, color: NSColor, yFraction: CGFloat) {
        guard !string.isEmpty else { return }
        let para = NSMutableParagraphStyle(); para.alignment = .center
        func attributed(_ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: para,
            ])
        }
        var size = rect.height * sizeFactor
        var str = attributed(size)
        let maxWidth = rect.width * 0.80
        while str.size().width > maxWidth && size > 8 {
            size -= 4; str = attributed(size)
        }
        let textSize = str.size()
        let origin = NSPoint(x: rect.midX - textSize.width / 2,
                             y: rect.minY + rect.height * yFraction - textSize.height / 2)
        str.draw(at: origin)
    }
}
