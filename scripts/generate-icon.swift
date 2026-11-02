#!/usr/bin/env swift
import AppKit
import Foundation

// Generates a genuine 1024x1024 RGBA bitmap at build time.
// Icon motif: one blue source folder branching into three numbered gold folders.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "FolderSpanner-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

func fillRound(_ rect: NSRect, radius: CGFloat, top: NSColor, bottom: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: 90)
}

func drawFolder(_ rect: NSRect, colorTop: NSColor, colorBottom: NSColor,
                tabWidth: CGFloat, label: String? = nil) {
    let tab = NSRect(x: rect.minX + 28, y: rect.maxY - 3, width: tabWidth, height: rect.height * 0.23)
    fillRound(tab, radius: 16, top: colorTop, bottom: colorBottom)
    let face = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.86)
    fillRound(face, radius: 29, top: colorTop, bottom: colorBottom)
    NSColor.white.withAlphaComponent(0.35).setStroke()
    let edge = NSBezierPath(roundedRect: face.insetBy(dx: 3, dy: 3), xRadius: 25, yRadius: 25)
    edge.lineWidth = 4
    edge.stroke()
    if let label {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 55, weight: .bold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (label as NSString).draw(in: NSRect(x: face.minX + 5, y: face.minY + 26,
                                            width: face.width - 10, height: 72),
                                 withAttributes: [.font: font,
                                                  .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.27, alpha: 1),
                                                  .paragraphStyle: style])
    }
}

image.lockFocus()
defer { image.unlockFocus() }

let background = NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964),
                              xRadius: 215, yRadius: 215)
background.addClip()
NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.54, blue: 0.95, alpha: 1),
           ending: NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.36, alpha: 1))?
    .draw(in: background, angle: 115)

drawFolder(NSRect(x: 190, y: 503, width: 644, height: 315),
           colorTop: NSColor(calibratedRed: 0.39, green: 0.85, blue: 1, alpha: 1),
           colorBottom: NSColor(calibratedRed: 0.02, green: 0.35, blue: 0.93, alpha: 1),
           tabWidth: 255)

let arrow = NSBezierPath()
arrow.lineWidth = 20
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 512, y: 520))
arrow.line(to: NSPoint(x: 512, y: 404))
arrow.move(to: NSPoint(x: 230, y: 404))
arrow.line(to: NSPoint(x: 794, y: 404))
for x in [230.0, 512.0, 794.0] {
    arrow.move(to: NSPoint(x: x, y: 404))
    arrow.line(to: NSPoint(x: x, y: 335))
}
NSColor(calibratedWhite: 1, alpha: 0.95).setStroke()
arrow.stroke()

let goldTop = NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.42, alpha: 1)
let goldBottom = NSColor(calibratedRed: 0.97, green: 0.56, blue: 0.04, alpha: 1)
for (i, x) in [84.0, 368.0, 652.0].enumerated() {
    drawFolder(NSRect(x: x, y: 140, width: 286, height: 204),
               colorTop: goldTop, colorBottom: goldBottom, tabWidth: 120,
               label: String(format: "%03d", i + 1))
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Cannot generate icon bitmap\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output), options: .atomic)
print("Created icon bitmap: \(output)")
