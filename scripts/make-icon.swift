// Draws the Stay Private app icon and writes a 1024px PNG.
//   swift scripts/make-icon.swift <output.png>
// scripts/make-icon.sh wraps this and produces assets/AppIcon.icns.
//
// The design is drawn from scratch (no stock symbols): a keyhole at the end of
// a tunnel. Three glowing rings, each broken at a different angle like the
// tumblers of a vault, recede toward a keyhole in the centre.
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
let centre = NSPoint(x: size / 2, y: size / 2 + 6)

// Drop shadow under the tile.
NSGraphicsContext.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
tileShadow.shadowBlurRadius = 28
tileShadow.shadowOffset = NSSize(width: 0, height: -12)
tileShadow.set()
rgb(0x0B1030).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Midnight background, lighter toward the centre so the tunnel has depth.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [rgb(0x070A1F), rgb(0x141A4A)])!.draw(in: tile, angle: 90)
NSGradient(colors: [rgb(0x3B2FB0, 0.75), rgb(0x1A1F5C, 0.35), rgb(0x0B1030, 0)])!
    .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: 430, options: [])
NSGraphicsContext.restoreGraphicsState()

// The rings: radius, line width, colour, where the gap is centred (degrees), gap size.
struct Ring { let radius, width: CGFloat; let color: NSColor; let gapAt, gap: CGFloat }
let rings = [
    Ring(radius: 312, width: 46, color: rgb(0x8B5CFF), gapAt: 38, gap: 64),
    Ring(radius: 232, width: 40, color: rgb(0x3F9BFF), gapAt: 168, gap: 72),
    Ring(radius: 156, width: 34, color: rgb(0x2EE6C3), gapAt: 292, gap: 84),
]
for ring in rings {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: centre, radius: ring.radius,
                  startAngle: ring.gapAt + ring.gap / 2, endAngle: ring.gapAt - ring.gap / 2 + 360)
    arc.lineWidth = ring.width
    arc.lineCapStyle = .round

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = ring.color.withAlphaComponent(0.75)
    glow.shadowBlurRadius = 34
    glow.shadowOffset = .zero
    glow.set()
    ring.color.setStroke()
    arc.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // A thin bright core makes the ring read as a lit tube rather than a flat line.
    let core = arc.copy() as! NSBezierPath
    core.lineWidth = ring.width * 0.28
    NSColor.white.withAlphaComponent(0.38).setStroke()
    core.stroke()
}

// The keyhole: a round head on a flared, round-bottomed stem.
let head = NSPoint(x: centre.x, y: centre.y + 24)
let headRadius: CGFloat = 50
let keyhole = NSBezierPath(ovalIn: NSRect(x: head.x - headRadius, y: head.y - headRadius,
                                           width: headRadius * 2, height: headRadius * 2))
let stem = NSBezierPath()
let topHalf: CGFloat = 24, bottomHalf: CGFloat = 42, stemTop = head.y - 22, stemBottom = head.y - 122
stem.move(to: NSPoint(x: head.x - topHalf, y: stemTop))
stem.line(to: NSPoint(x: head.x + topHalf, y: stemTop))
stem.line(to: NSPoint(x: head.x + bottomHalf, y: stemBottom + 12))
stem.curve(to: NSPoint(x: head.x + bottomHalf - 12, y: stemBottom),
           controlPoint1: NSPoint(x: head.x + bottomHalf + 2, y: stemBottom + 4),
           controlPoint2: NSPoint(x: head.x + bottomHalf - 4, y: stemBottom))
stem.line(to: NSPoint(x: head.x - bottomHalf + 12, y: stemBottom))
stem.curve(to: NSPoint(x: head.x - bottomHalf, y: stemBottom + 12),
           controlPoint1: NSPoint(x: head.x - bottomHalf + 4, y: stemBottom),
           controlPoint2: NSPoint(x: head.x - bottomHalf - 2, y: stemBottom + 4))
stem.close()
keyhole.append(stem.reversed)  // same winding as the head, so the overlap stays filled

NSGraphicsContext.saveGraphicsState()
let keyGlow = NSShadow()
keyGlow.shadowColor = rgb(0xBFFFF2, 0.9)
keyGlow.shadowBlurRadius = 40
keyGlow.shadowOffset = .zero
keyGlow.set()
rgb(0xF4FFFC).setFill()
keyhole.fill()
NSGraphicsContext.restoreGraphicsState()

// A faint sheen across the top of the tile.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(starting: NSColor.white.withAlphaComponent(0.10), ending: NSColor.white.withAlphaComponent(0))!
    .draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
