// The disk image's window, drawn rather than exported — like the icon. White,
// the app on the left and Applications on the right, one thin arrow between
// them and one line saying what to do. The Finder draws the two icons and
// their names on top; this draws everything else.
//
// Run by build.sh:  swift Installer/background.swift <folder>
// It writes background.png and background@2x.png; build.sh folds them into
// one background.tiff with tiffutil. The places here are the ones in
// Installer/dmg.py — change one, change the other.

import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// The window's content, in points, and where the two icons' centres sit in it,
/// measured from the top-left the way the Finder measures them.
let size = CGSize(width: 640, height: 380)
let app = CGPoint(x: 180, y: 145)
let applications = CGPoint(x: 460, y: 145)
/// Half of the Finder's 128-point icon, plus the air left either side of the arrow.
let clearance: CGFloat = 64 + 30

let ink = NSColor(white: 0.09, alpha: 1)
let muted = NSColor(white: 0.55, alpha: 1)

func draw() {
    NSColor.white.setFill()
    CGRect(origin: .zero, size: size).fill()

    // The arrow: a hairline from one icon to the other, and an open head.
    let y = size.height - app.y
    let start = app.x + clearance
    let end = applications.x - clearance
    let line = NSBezierPath()
    line.move(to: CGPoint(x: start, y: y))
    line.line(to: CGPoint(x: end, y: y))
    line.move(to: CGPoint(x: end - 7, y: y + 7))
    line.line(to: CGPoint(x: end, y: y))
    line.line(to: CGPoint(x: end - 7, y: y - 7))
    line.lineWidth = 1.5
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    ink.withAlphaComponent(0.3).setStroke()
    line.stroke()

    // What to do, once, under the names the Finder writes.
    let words = "Drag Satori into Applications to install it"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: muted,
    ]
    let text = NSAttributedString(string: words, attributes: attributes)
    let box = text.size()
    text.draw(at: CGPoint(x: (size.width - box.width) / 2, y: size.height - 282 - box.height / 2))
}

for (scale, name) in [(1, "background.png"), (2, "background@2x.png")] {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}
