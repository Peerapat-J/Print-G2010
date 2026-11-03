// Renders the app icon (a printer glyph on a blue rounded square) into the asset catalog.
// Run: swift scripts/make-icon.swift
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "app/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: the body fills 80% of the canvas, corner radius about 22.5% of the body.
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(red: 0.36, green: 0.66, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.10, green: 0.40, blue: 0.92, alpha: 1))!.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .regular)
    if let glyph = NSImage(systemSymbolName: "printer.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = glyph.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        glyph.draw(in: NSRect(origin: .zero, size: size))
        NSColor.white.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// (point size, scale) pairs required for a macOS app icon.
var images: [[String: String]] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try render(pt * scale).write(to: out.appendingPathComponent(name))
    images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
    .write(to: out.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("icon written to \(out.path)")
