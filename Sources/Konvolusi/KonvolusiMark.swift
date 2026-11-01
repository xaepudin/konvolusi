import AppKit

/// The Konvolusi mark shared by the menu bar and the in-app status header.
///
/// It is the app icon's off-center impulse/ripple, reduced to three rings so it
/// stays legible at menu bar size. The rings are clipped at the left edge on
/// purpose, matching how the app icon's outer rings leave the tile.
enum KonvolusiMark {
    static func image(running: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()

            let scale = min(rect.width, rect.height) / 18
            let center = NSPoint(x: rect.minX + 0.379 * rect.width, y: rect.midY)

            let rings: [(radius: CGFloat, width: CGFloat)] = [
                (3.4, 1.9),
                (6.3, 1.35),
                (9.2, 0.8),
            ]
            NSColor.black.withAlphaComponent(0.95).setStroke()
            for ring in rings {
                let path = NSBezierPath(ovalIn: NSRect(
                    x: center.x - ring.radius * scale,
                    y: center.y - ring.radius * scale,
                    width: ring.radius * 2 * scale,
                    height: ring.radius * 2 * scale
                ))
                path.lineWidth = ring.width * scale
                path.stroke()
            }

            let dotRect = NSRect(
                x: center.x - 2.05 * scale,
                y: center.y - 2.05 * scale,
                width: 4.1 * scale,
                height: 4.1 * scale
            )
            let dot = NSBezierPath(ovalIn: dotRect)
            if running {
                NSColor.black.setFill()
                dot.fill()
            } else {
                dot.lineWidth = 1.3 * scale
                NSColor.black.withAlphaComponent(0.9).setStroke()
                dot.stroke()
            }

            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
