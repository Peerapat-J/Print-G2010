// Renders the background of the disk image window: a title, a hint and an arrow from the app
// to the Applications shortcut. The icons themselves are placed by scripts/dmg/settings.py, so keep
// the coordinates below in sync with its icon_locations.
// Run: swift scripts/make-dmg-background.swift
import AppKit

// The window opens at 660 x 400 points, but Finder lets people resize it and does not stretch or tile
// the picture. So the canvas is much larger than the window, with the gradient ending in a flat
// colour, and a bigger window still shows the same background.
let width = 660.0
let height = 400.0
let canvasWidth = 2000.0
let canvasHeight = 1400.0
let topColor = NSColor(red: 0.98, green: 0.985, blue: 1.0, alpha: 1)
let bottomColor = NSColor(red: 0.90, green: 0.925, blue: 0.96, alpha: 1)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "scripts/dmg")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Icon centres, in points from the top left of the window (also used by scripts/dmg/settings.py).
let iconY = 190.0
let appX = 180.0
let applicationsX = 480.0

let ink = NSColor(red: 0.11, green: 0.14, blue: 0.20, alpha: 1)
let secondary = NSColor(red: 0.42, green: 0.45, blue: 0.52, alpha: 1)
let blue = NSColor(red: 0.18, green: 0.44, blue: 0.93, alpha: 1)

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasWidth) * scale,
                               pixelsHigh: Int(canvasHeight) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    // Report the size in points so the 2x image is tagged 144 dpi and Finder shows it sharp.
    rep.size = NSSize(width: canvasWidth, height: canvasHeight)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // AppKit's y axis points up, and the window shows the top left corner of the canvas.
    bottomColor.setFill()
    NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight).fill()
    NSGradient(starting: topColor, ending: bottomColor)!
        .draw(in: NSRect(x: 0, y: canvasHeight - height, width: canvasWidth, height: height), angle: -90)

    func centred(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, fromTop y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        s.draw(at: NSPoint(x: (width - s.size().width) / 2, y: canvasHeight - y - s.size().height))
    }
    centred("Install Print G2010", size: 26, weight: .semibold, color: ink, fromTop: 44)
    centred("Drag the app onto the Applications folder", size: 14, weight: .regular, color: secondary, fromTop: 82)

    // Arrow between the two icons (AppKit's y axis points up).
    let y = canvasHeight - iconY
    let tail = appX + 100
    let head = applicationsX - 100
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: tail, y: y))
    shaft.line(to: NSPoint(x: head - 14, y: y))
    shaft.lineWidth = 7
    shaft.lineCapStyle = .round
    blue.setStroke()
    shaft.stroke()
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: head + 6, y: y))
    tip.line(to: NSPoint(x: head - 20, y: y + 17))
    tip.line(to: NSPoint(x: head - 20, y: y - 17))
    tip.close()
    blue.setFill()
    tip.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
print("wrote \(out.path)/background.png and background@2x.png")
