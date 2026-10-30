// Draws the MythosTable app icon and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Rounded-square tile with the macOS icon grid inset.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.13, green: 0.22, blue: 0.18, alpha: 1),
                        NSColor(red: 0.04, green: 0.07, blue: 0.06, alpha: 1)])!
        .draw(in: tilePath, angle: -90)

    let center = NSPoint(x: 512 * s, y: 512 * s)
    let gold = NSColor(red: 0.86, green: 0.72, blue: 0.40, alpha: 1)

    // Five-pointed star outline.
    let star = NSBezierPath()
    for i in 0..<10 {
        let r = (i % 2 == 0 ? 300 : 125) * s
        let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
        let p = NSPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
        i == 0 ? star.move(to: p) : star.line(to: p)
    }
    star.close()
    star.lineWidth = 22 * s
    star.lineJoinStyle = .round
    gold.setStroke()
    star.stroke()

    // Eye at the center.
    let eye = NSBezierPath()
    eye.move(to: NSPoint(x: center.x - 120 * s, y: center.y))
    eye.curve(to: NSPoint(x: center.x + 120 * s, y: center.y),
              controlPoint1: NSPoint(x: center.x - 50 * s, y: center.y + 85 * s),
              controlPoint2: NSPoint(x: center.x + 50 * s, y: center.y + 85 * s))
    eye.curve(to: NSPoint(x: center.x - 120 * s, y: center.y),
              controlPoint1: NSPoint(x: center.x + 50 * s, y: center.y - 85 * s),
              controlPoint2: NSPoint(x: center.x - 50 * s, y: center.y - 85 * s))
    NSColor(red: 0.95, green: 0.90, blue: 0.75, alpha: 1).setFill()
    eye.fill()
    let pupil = NSBezierPath(ovalIn: NSRect(x: center.x - 34 * s, y: center.y - 34 * s, width: 68 * s, height: 68 * s))
    NSColor(red: 0.45, green: 0.08, blue: 0.08, alpha: 1).setFill()
    pupil.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try draw(size: CGFloat(base * scale)).write(to: out.appendingPathComponent(name))
    }
}
