#!/usr/bin/env swift
import AppKit
import Foundation

// Original FolderSpanner artwork: layered rounded blue tiles. The window header
// uses NSApp.applicationIconImage, so the application and its UI show *exactly*
// the same generated bitmap, with no separate SF Symbol or branding drift.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "FolderSpanner-1024.png"
let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let icon = NSImage(size: canvas.size)

func rounded(_ rect: NSRect, radius: CGFloat, gradient: NSGradient) {
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    gradient.draw(in: rect, angle: 120)
    NSGraphicsContext.restoreGraphicsState()
}

icon.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

// Light, neutral rounded app tile, with a subtle border for dark/light desktops.
let tile = NSRect(x: 34, y: 34, width: 956, height: 956)
rounded(tile, radius: 214, gradient: NSGradient(
    starting: NSColor(calibratedRed: 0.99, green: 0.995, blue: 1, alpha: 1),
    ending: NSColor(calibratedRed: 0.86, green: 0.92, blue: 1, alpha: 1))!)
let border = NSBezierPath(roundedRect: tile.insetBy(dx: 6, dy: 6), xRadius: 208, yRadius: 208)
border.lineWidth = 8
NSColor(calibratedRed: 0.68, green: 0.78, blue: 0.94, alpha: 0.44).setStroke()
border.stroke()

let layers: [(CGRect, CGFloat, NSColor, NSColor)] = [
    (CGRect(x: 178, y: 365, width: 490, height: 490), 98,
     NSColor(calibratedRed: 0.53, green: 0.78, blue: 1, alpha: 1),
     NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.90, alpha: 1)),
    (CGRect(x: 263, y: 272, width: 490, height: 490), 98,
     NSColor(calibratedRed: 0.28, green: 0.65, blue: 1, alpha: 1),
     NSColor(calibratedRed: 0.06, green: 0.32, blue: 0.85, alpha: 1)),
    (CGRect(x: 350, y: 178, width: 490, height: 490), 98,
     NSColor(calibratedRed: 0.16, green: 0.55, blue: 1, alpha: 1),
     NSColor(calibratedRed: 0.02, green: 0.25, blue: 0.75, alpha: 1))
]

for (rect, radius, top, bottom) in layers {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.0, green: 0.16, blue: 0.42, alpha: 0.26)
    shadow.shadowBlurRadius = 19
    shadow.shadowOffset = NSSize(width: 0, height: -13)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    rounded(rect, radius: radius, gradient: NSGradient(starting: top, ending: bottom)!)
    NSGraphicsContext.restoreGraphicsState()

    // Highlights make overlapping tile boundaries legible at Dock icon sizes.
    let stroke = NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6),
                              xRadius: radius - 6, yRadius: radius - 6)
    stroke.lineWidth = 9
    NSColor.white.withAlphaComponent(0.28).setStroke()
    stroke.stroke()
}

icon.unlockFocus()
guard let tiff = icon.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to generate FolderSpanner icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output), options: .atomic)
print("Generated FolderSpanner bitmap: \(output)")
