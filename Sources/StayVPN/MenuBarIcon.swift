import AppKit

/// Menu bar versions of the app icon (a keyhole inside broken rings).
///
/// - connected: the full-colour app icon
/// - disconnected: the same design as a single-colour glyph that follows the
///   menu bar's light or dark appearance
/// - busy (connecting, disconnecting, no response): the glyph without its keyhole
enum MenuBarIcon {
    enum Style { case connected, disconnected, busy }

    static func image(_ style: Style) -> NSImage {
        switch style {
        case .connected: return colour ?? glyph(keyhole: true)
        case .disconnected: return glyph(keyhole: true)
        case .busy: return glyph(keyhole: false)
        }
    }

    /// The app icon scaled for the menu bar. Nil when not running from the app bundle.
    private static let colour: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return nil }
        // The artwork has a transparent margin, so 22pt gives a tile about 18pt wide.
        icon.size = NSSize(width: 22, height: 22)
        return icon
    }()

    private static let glyphs: [Bool: NSImage] = [true: drawGlyph(keyhole: true), false: drawGlyph(keyhole: false)]

    private static func glyph(keyhole: Bool) -> NSImage { glyphs[keyhole]! }

    /// Draws the simplified design: two rings (three would blur together at this size) and the keyhole.
    static func drawGlyph(keyhole: Bool) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let centre = NSPoint(x: side / 2, y: side / 2)
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // radius, line width, gap centre (degrees), gap size (same angles as the app icon)
            let rings: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(7.7, 1.5, 38, 62), (4.7, 1.4, 208, 84)]
            for (radius, width, gapAt, gap) in rings {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: centre, radius: radius,
                              startAngle: gapAt + gap / 2, endAngle: gapAt - gap / 2 + 360)
                arc.lineWidth = width
                arc.lineCapStyle = .round
                arc.stroke()
            }

            if keyhole {
                let head = NSPoint(x: centre.x, y: centre.y + 0.9)
                let radius: CGFloat = 1.55
                NSBezierPath(ovalIn: NSRect(x: head.x - radius, y: head.y - radius,
                                            width: radius * 2, height: radius * 2)).fill()
                let stem = NSBezierPath()
                stem.move(to: NSPoint(x: head.x - 0.75, y: head.y))
                stem.line(to: NSPoint(x: head.x + 0.75, y: head.y))
                stem.line(to: NSPoint(x: head.x + 1.35, y: head.y - 3.3))
                stem.line(to: NSPoint(x: head.x - 1.35, y: head.y - 3.3))
                stem.close()
                stem.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
