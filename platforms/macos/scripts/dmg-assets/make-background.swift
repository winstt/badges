import AppKit

// DMG window is 520x360 (see release.sh). Render at 2x for retina crispness.
let scale: CGFloat = 2
let w: CGFloat = 520, h: CGFloat = 360
let pxW = Int(w * scale), pxH = Int(h * scale)

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no ctx")
}
ctx.scaleBy(x: scale, y: scale)              // now draw in 520x360 point space
let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = nsctx

// Background: soft vertical gradient, near-white.
let top = NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.99, alpha: 1)
let bottom = NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)
let grad = NSGradient(starting: top, ending: bottom)!
grad.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)

// Brand red accent.
let red = NSColor(calibratedRed: 0.86, green: 0.16, blue: 0.13, alpha: 1)

// Title near the top.
let titleStyle = NSMutableParagraphStyle(); titleStyle.alignment = .center
let title = NSAttributedString(string: "Badges", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .bold),
    .foregroundColor: NSColor(white: 0.13, alpha: 1),
    .paragraphStyle: titleStyle,
])
title.draw(in: NSRect(x: 0, y: h - 66, width: w, height: 40))

let subStyle = NSMutableParagraphStyle(); subStyle.alignment = .center
let sub = NSAttributedString(string: "Drag Badges to your Applications folder", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(white: 0.45, alpha: 1),
    .paragraphStyle: subStyle,
])
sub.draw(in: NSRect(x: 0, y: h - 92, width: w, height: 20))

// Arrow between the app icon (x=140) and the Applications drop link (x=380),
// centered on the icon row (release.sh places both at y=180 from the TOP).
// CoreGraphics origin is bottom-left, so that row sits at y = h - 180 = 180.
let rowY = h - 180
let startX: CGFloat = 205, endX: CGFloat = 315
let path = NSBezierPath()
path.lineWidth = 6
path.lineCapStyle = .round
path.move(to: NSPoint(x: startX, y: rowY))
path.line(to: NSPoint(x: endX, y: rowY))
red.setStroke()
path.stroke()
// Arrow head.
let head = NSBezierPath()
head.move(to: NSPoint(x: endX + 10, y: rowY))
head.line(to: NSPoint(x: endX - 6, y: rowY + 11))
head.line(to: NSPoint(x: endX - 6, y: rowY - 11))
head.close()
red.setFill()
head.fill()

NSGraphicsContext.current = nil
guard let img = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: img)
let data = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(pxW)x\(pxH))")
