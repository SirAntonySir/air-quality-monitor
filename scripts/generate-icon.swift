#!/usr/bin/env swift

import Cocoa

// Generate a 1024x1024 app icon
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)

// Background gradient: dark blue-green
let gradient = NSGradient(colors: [
    NSColor(red: 0.05, green: 0.12, blue: 0.20, alpha: 1.0),
    NSColor(red: 0.08, green: 0.20, blue: 0.30, alpha: 1.0),
    NSColor(red: 0.04, green: 0.15, blue: 0.22, alpha: 1.0),
])!
gradient.draw(in: rect, angle: -45)

// Draw a stylized air quality wave/chart line
let path = NSBezierPath()
path.lineWidth = 28
path.lineCapStyle = .round
path.lineJoinStyle = .round

// Chart line path — a smooth wave representing sensor data
let baseY = Double(size) * 0.45
let amplitude = Double(size) * 0.18

let points: [(Double, Double)] = [
    (0.10, 0.50), (0.18, 0.62), (0.26, 0.70), (0.34, 0.65),
    (0.42, 0.48), (0.50, 0.38), (0.58, 0.42), (0.66, 0.55),
    (0.74, 0.68), (0.82, 0.60), (0.90, 0.45)
]

// Draw using smooth curve
for (i, point) in points.enumerated() {
    let x = point.0 * Double(size)
    let y = point.1 * Double(size)
    if i == 0 {
        path.move(to: NSPoint(x: x, y: y))
    } else {
        let prev = points[i - 1]
        let prevX = prev.0 * Double(size)
        let prevY = prev.1 * Double(size)
        let cpx1 = prevX + (x - prevX) * 0.4
        let cpx2 = x - (x - prevX) * 0.4
        path.curve(to: NSPoint(x: x, y: y),
                    controlPoint1: NSPoint(x: cpx1, y: prevY),
                    controlPoint2: NSPoint(x: cpx2, y: y))
    }
}

// Glow effect: draw wider translucent line first
let glowPath = path.copy() as! NSBezierPath
glowPath.lineWidth = 56
NSColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 0.15).setStroke()
glowPath.stroke()

let glowPath2 = path.copy() as! NSBezierPath
glowPath2.lineWidth = 36
NSColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 0.25).setStroke()
glowPath2.stroke()

// Main line: teal/green gradient feel
NSColor(red: 0.3, green: 0.85, blue: 0.65, alpha: 1.0).setStroke()
path.stroke()

// Draw a small dot at the end (current value indicator)
let lastPoint = points.last!
let dotCenter = NSPoint(x: lastPoint.0 * Double(size), y: lastPoint.1 * Double(size))
let dotRadius: CGFloat = 14
let dotRect = NSRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius,
                     width: dotRadius * 2, height: dotRadius * 2)
NSColor(red: 0.3, green: 0.85, blue: 0.65, alpha: 1.0).setFill()
NSBezierPath(ovalIn: dotRect).fill()

// Outer glow for dot
let dotGlowRect = NSRect(x: dotCenter.x - dotRadius * 2.5, y: dotCenter.y - dotRadius * 2.5,
                          width: dotRadius * 5, height: dotRadius * 5)
NSColor(red: 0.3, green: 0.85, blue: 0.65, alpha: 0.2).setFill()
NSBezierPath(ovalIn: dotGlowRect).fill()

// Draw a subtle threshold line (dashed)
let thresholdPath = NSBezierPath()
thresholdPath.move(to: NSPoint(x: Double(size) * 0.08, y: Double(size) * 0.68))
thresholdPath.line(to: NSPoint(x: Double(size) * 0.92, y: Double(size) * 0.68))
thresholdPath.lineWidth = 3
thresholdPath.setLineDash([12, 8], count: 2, phase: 0)
NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.4).setStroke()
thresholdPath.stroke()

// Draw subtle grid lines
for i in 1..<4 {
    let gridPath = NSBezierPath()
    let y = Double(size) * (0.25 + Double(i) * 0.15)
    gridPath.move(to: NSPoint(x: Double(size) * 0.08, y: y))
    gridPath.line(to: NSPoint(x: Double(size) * 0.92, y: y))
    gridPath.lineWidth = 1
    NSColor.white.withAlphaComponent(0.06).setStroke()
    gridPath.stroke()
}

image.unlockFocus()

// Save as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Icon saved to \(outputPath)")
