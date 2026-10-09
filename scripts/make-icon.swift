// Draws Clipjar's app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift  (run from the repository root; needs sips and iconutil)
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// A clip card: a coloured rounded rectangle with two "text" lines, rotated about its centre.
func card(center: NSPoint, angle: CGFloat, fill: NSColor) {
    let size = NSSize(width: 330, height: 120)
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.rotate(byDegrees: angle)
    t.concat()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.shadowBlurRadius = 14
    shadow.set()
    fill.setFill()
    roundedRect(NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), 26).fill()
    NSShadow().set()
    color(0xFFFFFF, 0.85).setFill()
    roundedRect(NSRect(x: -size.width / 2 + 34, y: 8, width: 200, height: 22), 11).fill()
    color(0xFFFFFF, 0.6).setFill()
    roundedRect(NSRect(x: -size.width / 2 + 34, y: -32, width: 140, height: 22), 11).fill()
    NSGraphicsContext.restoreGraphicsState()
}

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

// Background tile on the macOS icon grid (824 pt with a soft drop shadow).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
NSGraphicsContext.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = color(0x000000, 0.3)
tileShadow.shadowOffset = NSSize(width: 0, height: -10)
tileShadow.shadowBlurRadius = 24
tileShadow.set()
color(0x2B2F6B).setFill()
roundedRect(tile, 185).fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0x5B6CF0), ending: color(0x2A2370))!.draw(in: roundedRect(tile, 185), angle: -90)

// Jar body: frosted glass.
let body = roundedRect(NSRect(x: 292, y: 196, width: 440, height: 500), 96)
color(0xFFFFFF, 0.16).setFill()
body.fill()

// Clips stacked inside the jar, clipped to its outline.
NSGraphicsContext.saveGraphicsState()
body.addClip()
card(center: NSPoint(x: 505, y: 300), angle: 6, fill: color(0x2EC4A6))
card(center: NSPoint(x: 518, y: 420), angle: -7, fill: color(0xFFC145))
card(center: NSPoint(x: 508, y: 540), angle: 4, fill: color(0xFF6B6B))
NSGraphicsContext.restoreGraphicsState()

// Glass rim and highlight.
color(0xFFFFFF, 0.8).setStroke()
body.lineWidth = 16
body.stroke()
color(0xFFFFFF, 0.35).setFill()
roundedRect(NSRect(x: 330, y: 300, width: 28, height: 300), 14).fill()

// Lid.
let lid = roundedRect(NSRect(x: 318, y: 696, width: 388, height: 92), 28)
NSGradient(starting: color(0xFFB347), ending: color(0xF07C1A))!.draw(in: lid, angle: -90)
color(0xFFFFFF, 0.3).setFill()
roundedRect(NSRect(x: 340, y: 752, width: 344, height: 16), 8).fill()

image.unlockFocus()

let fm = FileManager.default
let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("clipjar-icon-\(getpid())")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = work.appendingPathComponent("icon-1024.png")
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: master)

func run(_ tool: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw NSError(domain: tool, code: Int(p.terminationStatus)) }
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try run("/usr/bin/sips", ["-z", "\(px)", "\(px)", master.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"])
try? fm.removeItem(at: work)
print("Wrote Resources/AppIcon.icns")
