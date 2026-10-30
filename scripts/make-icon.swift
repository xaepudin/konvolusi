#!/usr/bin/env swift
// Draws the Konvolusi app icon at 1024×1024 and writes a PNG.
// Run `scripts/make-icon.swift Resources/AppIcon-1024.png` from the repo root.
import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon-1024.png"
let size = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: size,
                                    pixelsHigh: size,
                                    bitsPerSample: 8,
                                    samplesPerPixel: 4,
                                    hasAlpha: true,
                                    isPlanar: false,
                                    colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0,
                                    bitsPerPixel: 0) else {
    fatalError("could not allocate the icon bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor.clear.setFill()
canvas.fill()

let tile = NSRect(x: 48, y: 48, width: 928, height: 928)
let rounded = NSBezierPath(roundedRect: tile, xRadius: 210, yRadius: 210)

// Deep aubergine to teal. The warm ripple is deliberately unlike the green
// heartbeat line used by Activity Monitor.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.095, green: 0.062, blue: 0.190, alpha: 1),
    NSColor(calibratedRed: 0.035, green: 0.190, blue: 0.240, alpha: 1),
])!
gradient.draw(in: rounded, angle: -58)

rounded.addClip()

// A quiet highlight across the top.
let highlight = NSBezierPath(ovalIn: NSRect(x: 100, y: 590, width: 824, height: 380))
NSColor.white.withAlphaComponent(0.040).setFill()
highlight.fill()

// A single impulse and the room's response: concentric ripples spreading to
// the right. The rings are clipped by the left edge of the tile, so the icon
// reads as a source with a decaying response rather than an EKG trace.
let center = NSPoint(x: 388, y: 512)
let rings: [(radius: CGFloat, width: CGFloat, color: NSColor, alpha: CGFloat)] = [
    (118, 36, NSColor(calibratedRed: 1.000, green: 0.835, blue: 0.690, alpha: 1), 0.98),
    (218, 30, NSColor(calibratedRed: 1.000, green: 0.690, blue: 0.520, alpha: 1), 0.76),
    (318, 24, NSColor(calibratedRed: 1.000, green: 0.500, blue: 0.400, alpha: 1), 0.52),
    (418, 18, NSColor(calibratedRed: 1.000, green: 0.360, blue: 0.360, alpha: 1), 0.32),
    (512, 13, NSColor(calibratedRed: 0.950, green: 0.260, blue: 0.350, alpha: 1), 0.18),
]

for ring in rings {
    let circle = NSBezierPath(ovalIn: NSRect(x: center.x - ring.radius,
                                            y: center.y - ring.radius,
                                            width: ring.radius * 2,
                                            height: ring.radius * 2))
    circle.lineWidth = ring.width
    ring.color.withAlphaComponent(ring.alpha).setStroke()
    circle.stroke()
}

// The impulse itself.
let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 38, y: center.y - 38, width: 76, height: 76))
NSColor(calibratedRed: 1.000, green: 0.965, blue: 0.900, alpha: 0.98).setFill()
dot.fill()

let core = NSBezierPath(ovalIn: NSRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32))
NSColor(calibratedRed: 1.000, green: 0.500, blue: 0.400, alpha: 0.95).setFill()
core.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("could not encode the icon PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (\(size)×\(size))")
