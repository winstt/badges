import AppKit

/// Renders an on-brand badge in the house style seen in the real artwork
/// (`~/Desktop/BADGES/badges ikonky.ai`): a rounded document card with a folded
/// top-right corner, a **thick coloured outline**, a **dark inner fill**, a big app
/// glyph in the outline colour, and the file-type label in white underneath — the
/// same look as the bundled PSD ("Ps"/"PSD") and AI ("Ai"/"AI") art.
enum BadgeGenerator {

    /// Full control: separate outline (also the glyph colour) and inner fill.
    static func makePNG(glyph: String, label: String, outline: NSColor, fill: NSColor,
                        side: CGFloat = 1024) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high

        let stroke = outline.usingColorSpace(.deviceRGB) ?? outline
        let bg = fill.usingColorSpace(.deviceRGB) ?? fill

        // Card geometry — proportions eyeballed from the real AI/PSD badges: a portrait
        // document (taller than wide) with a folded top-right corner.
        let lineWidth = side * 0.052
        let hInset = side * 0.135 + lineWidth / 2           // wider side margins → portrait card
        let vInset = side * 0.050 + lineWidth / 2
        let rect = NSRect(x: hInset, y: vInset, width: side - 2 * hInset, height: side - 2 * vInset)
        let radius = side * 0.075
        let chamfer = rect.width * 0.34                      // the folded top-right corner

        let path = documentPath(rect: rect, radius: radius, chamfer: chamfer)
        bg.setFill(); path.fill()
        stroke.setStroke(); path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.stroke()

        // Big app glyph (e.g. "Ai") in the outline colour, sitting in the upper half.
        drawText(glyph, in: rect, sizeFactor: 0.42, color: stroke, yFraction: 0.60)
        // File-type label (e.g. "AI") in white along the bottom.
        drawText(label.uppercased(), in: rect, sizeFactor: 0.18, color: .white, yFraction: 0.20)

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Convenience: pick one accent colour; the dark inner fill is derived from it (a
    /// deep, rich tint — navy for blue, maroon for orange, matching the real art).
    static func makePNG(glyph: String, label: String, color: NSColor, side: CGFloat = 1024) -> Data? {
        makePNG(glyph: glyph, label: label, outline: color, fill: darkFill(from: color), side: side)
    }

    static func makeImage(glyph: String, label: String, outline: NSColor, fill: NSColor,
                          side: CGFloat = 256) -> NSImage? {
        makePNG(glyph: glyph, label: label, outline: outline, fill: fill, side: side).flatMap { NSImage(data: $0) }
    }

    static func makeImage(glyph: String, label: String, color: NSColor, side: CGFloat = 256) -> NSImage? {
        makeImage(glyph: glyph, label: label, outline: color, fill: darkFill(from: color), side: side)
    }

    /// A deep, dark tint of the accent colour to use as the inner fill: keep the hue,
    /// hold saturation high, drop brightness way down. Greys collapse to near-black.
    static func darkFill(from color: NSColor) -> NSColor {
        guard let c = color.usingColorSpace(.deviceRGB) else { return .black }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(deviceHue: h, saturation: min(1, s * 1.05), brightness: 0.15, alpha: 1)
    }

    // MARK: - Shape

    /// Document outline: rounded top-left / bottom-left / bottom-right corners and a
    /// straight chamfer across the top-right (the "folded corner"), with the corners
    /// where the chamfer meets the edges lightly rounded too.
    private static func documentPath(rect: NSRect, radius: CGFloat, chamfer: CGFloat) -> NSBezierPath {
        let foldR = radius * 0.6
        let p = NSBezierPath()
        p.move(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        // top edge → rounded into the chamfer
        p.appendArc(from: NSPoint(x: rect.maxX - chamfer, y: rect.maxY),
                    to: NSPoint(x: rect.maxX, y: rect.maxY - chamfer), radius: foldR)
        // chamfer → rounded into the right edge
        p.appendArc(from: NSPoint(x: rect.maxX, y: rect.maxY - chamfer),
                    to: NSPoint(x: rect.maxX, y: rect.minY), radius: foldR)
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

    /// The house font is **Myriad Pro Bold** (the Adobe badge font). Fall back through
    /// its other weights, then to a heavy system font, so generation still works on
    /// machines without the full Adobe font set installed.
    static func badgeFont(ofSize size: CGFloat) -> NSFont {
        for name in ["MyriadPro-Bold", "MyriadPro-Semibold"] {
            if let f = NSFont(name: name, size: size) { return f }
        }
        if let regular = NSFont(name: "MyriadPro-Regular", size: size) {
            let bold = NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask)
            return bold
        }
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    private static func drawText(_ string: String, in rect: NSRect,
                                 sizeFactor: CGFloat, color: NSColor, yFraction: CGFloat) {
        guard !string.isEmpty else { return }
        let para = NSMutableParagraphStyle(); para.alignment = .center
        func attributed(_ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: badgeFont(ofSize: size),
                .foregroundColor: color,
                .paragraphStyle: para,
            ])
        }
        var size = rect.height * sizeFactor
        var str = attributed(size)
        let maxWidth = rect.width * 0.74
        while str.size().width > maxWidth && size > 8 {
            size -= 4; str = attributed(size)
        }
        let textSize = str.size()
        let origin = NSPoint(x: rect.midX - textSize.width / 2,
                             y: rect.minY + rect.height * yFraction - textSize.height / 2)
        str.draw(at: origin)
    }
}
