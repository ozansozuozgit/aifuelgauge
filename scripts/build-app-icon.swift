#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: build-app-icon.swift <output.iconset>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let fileManager = FileManager.default
try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let iconSpecs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: Int) -> NSImage {
    let scale = CGFloat(size) / 1024
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    bounds.fill()

    let cornerRadius = 226 * scale
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 40 * scale, dy: 40 * scale), xRadius: cornerRadius, yRadius: cornerRadius)
    let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.16, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.05, alpha: 1)
    ])
    backgroundGradient?.draw(in: background, angle: -35)

    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    background.lineWidth = max(1, 18 * scale)
    background.stroke()

    let gaugeRect = NSRect(x: 180 * scale, y: 210 * scale, width: 664 * scale, height: 432 * scale)
    let gauge = NSBezierPath()
    gauge.appendArc(
        withCenter: NSPoint(x: gaugeRect.midX, y: gaugeRect.minY),
        radius: gaugeRect.width / 2,
        startAngle: 22,
        endAngle: 158,
        clockwise: false
    )
    NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
    gauge.lineWidth = max(4, 72 * scale)
    gauge.lineCapStyle = .round
    gauge.stroke()

    let activeGauge = NSBezierPath()
    activeGauge.appendArc(
        withCenter: NSPoint(x: gaugeRect.midX, y: gaugeRect.minY),
        radius: gaugeRect.width / 2,
        startAngle: 22,
        endAngle: 116,
        clockwise: false
    )
    NSColor(calibratedRed: 0.27, green: 0.82, blue: 0.45, alpha: 1).setStroke()
    activeGauge.lineWidth = max(4, 72 * scale)
    activeGauge.lineCapStyle = .round
    activeGauge.stroke()

    let center = NSPoint(x: 512 * scale, y: 238 * scale)
    NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 44 * scale, y: center.y - 44 * scale, width: 88 * scale, height: 88 * scale)).fill()

    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: NSPoint(x: 675 * scale, y: 464 * scale))
    NSColor(calibratedRed: 0.82, green: 0.96, blue: 0.87, alpha: 1).setStroke()
    needle.lineWidth = max(2, 34 * scale)
    needle.lineCapStyle = .round
    needle.stroke()

    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: 462 * scale, y: 760 * scale))
    bolt.line(to: NSPoint(x: 590 * scale, y: 760 * scale))
    bolt.line(to: NSPoint(x: 536 * scale, y: 636 * scale))
    bolt.line(to: NSPoint(x: 646 * scale, y: 636 * scale))
    bolt.line(to: NSPoint(x: 444 * scale, y: 360 * scale))
    bolt.line(to: NSPoint(x: 490 * scale, y: 556 * scale))
    bolt.line(to: NSPoint(x: 386 * scale, y: 556 * scale))
    bolt.close()
    NSColor(calibratedRed: 0.31, green: 0.93, blue: 0.58, alpha: 1).setFill()
    bolt.fill()

    return image
}

func writePNG(_ image: NSImage, to url: URL, pixelSize: Int) throws {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

for spec in iconSpecs {
    try writePNG(drawIcon(size: spec.size), to: outputURL.appendingPathComponent(spec.name), pixelSize: spec.size)
}
