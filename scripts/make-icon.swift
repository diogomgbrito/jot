// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    // Squircle base with soft drop shadow (macOS icon grid: 824pt body inset 100pt).
    let base = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    NSColor.orange.setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 1.00, green: 0.83, blue: 0.30, alpha: 1),
               ending: NSColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1))!.draw(in: base, angle: -90)

    // Note card, slightly tilted.
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: 512 * s, yBy: 512 * s)
    t.rotate(byDegrees: -6)
    t.translateX(by: -512 * s, yBy: -512 * s)
    t.concat()
    let card = NSBezierPath(roundedRect: r(250, 220, 524, 600), xRadius: 56 * s, yRadius: 56 * s)
    let cardShadow = NSShadow()
    cardShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    cardShadow.shadowOffset = NSSize(width: 0, height: -14 * s)
    cardShadow.shadowBlurRadius = 30 * s
    NSGraphicsContext.saveGraphicsState()
    cardShadow.set()
    NSColor(white: 0.995, alpha: 1).setFill()
    card.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Title bar line.
    NSColor(white: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: r(320, 690, 300, 44), xRadius: 22 * s, yRadius: 22 * s).fill()

    // Checkbox with tick.
    let accent = NSColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1)
    accent.setFill()
    NSBezierPath(roundedRect: r(320, 560, 76, 76), xRadius: 18 * s, yRadius: 18 * s).fill()
    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: 337 * s, y: 598 * s))
    tick.line(to: NSPoint(x: 352 * s, y: 580 * s))
    tick.line(to: NSPoint(x: 380 * s, y: 618 * s))
    tick.lineWidth = 12 * s
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    NSColor.white.setStroke()
    tick.stroke()
    NSColor(white: 0.78, alpha: 1).setFill()
    NSBezierPath(roundedRect: r(426, 580, 260, 36), xRadius: 18 * s, yRadius: 18 * s).fill()

    // Body lines.
    for (i, w) in [366.0, 300, 340, 220].enumerated() {
        NSBezierPath(roundedRect: r(320, 470 - CGFloat(i) * 70, CGFloat(w), 32), xRadius: 16 * s, yRadius: 16 * s).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
        let data = render(CGFloat(pt * scale)).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
try! render(1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
