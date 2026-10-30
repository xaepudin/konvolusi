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

// Transparent canvas.
NSColor.clear.setFill()
canvas.fill()

let tile = NSRect(x: 48, y: 48, width: 928, height: 928)
let rounded = NSBezierPath(roundedRect: tile, xRadius: 210, yRadius: 210)

// Deep navy to teal, the same family as the menu bar waveform.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.045, green: 0.070, blue: 0.125, alpha: 1),
    NSColor(calibratedRed: 0.035, green: 0.235, blue: 0.265, alpha: 1),
])!
gradient.draw(in: rounded, angle: -62)

// Keep the rest of the drawing inside the rounded tile.
rounded.addClip()

// Soft concentric rings: a room around the impulse.
for index in 0..<5 {
    let inset = CGFloat(150 + index * 92)
    let ring = NSBezierPath(ovalIn: tile.insetBy(dx: inset, dy: inset))
    ring.lineWidth = CGFloat(3 + index)
    NSColor.white.withAlphaComponent(0.055 - CGFloat(index) * 0.008).setStroke()
    ring.stroke()
}

// A subtle top highlight.
let highlight = NSBezierPath(ovalIn: NSRect(x: 110, y: 560, width: 804, height: 430))
NSColor.white.withAlphaComponent(0.045).setFill()
highlight.fill()

// Baseline.
let baseline = NSBezierPath()
baseline.move(to: NSPoint(x: 150, y: 500))
baseline.line(to: NSPoint(x: 874, y: 500))
baseline.lineWidth = 4
NSColor.white.withAlphaComponent(0.18).setStroke()
baseline.stroke()

// The impulse and its decaying tail.
func waveform(alpha: CGFloat, scale: CGFloat, phase: Double, width: CGFloat) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    let count = 720
    for index in 0...count {
        let t = Double(index) / Double(count)
        let x = 178 + CGFloat(t) * 668
        let envelope = exp(-3.7 * t)
        let y = 500 + 238 * scale * CGFloat(envelope * cos(t * 26 + phase))
        let point = NSPoint(x: x, y: y)
        if index == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    NSColor(calibratedRed: 0.72, green: 0.98, blue: 0.96, alpha: alpha).setStroke()
    path.stroke()
}

// Ghost trace for depth, then the bright trace.
waveform(alpha: 0.22, scale: 1.06, phase: 0.55, width: 26)
waveform(alpha: 0.96, scale: 1.0, phase: 0.0, width: 19)

// Direct-arrival spike.
let spike = NSBezierPath()
spike.move(to: NSPoint(x: 178, y: 500))
spike.line(to: NSPoint(x: 178, y: 738))
spike.lineWidth = 19
spike.lineCapStyle = .round
NSColor(calibratedRed: 0.72, green: 0.98, blue: 0.96, alpha: 0.96).setStroke()
spike.stroke()

// A small dot marks the arrival.
let dot = NSBezierPath(ovalIn: NSRect(x: 158, y: 738, width: 40, height: 40))
NSColor.white.withAlphaComponent(0.95).setFill()
dot.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("could not encode the icon PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (\(size)×\(size))")
