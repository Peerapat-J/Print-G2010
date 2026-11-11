// Makes a 3-page A4 PDF for timing the printer in the different colour / dpi modes:
//   page 1  black text only (a typical document)
//   page 2  text with a few colour pictures (a typical worksheet)
//   page 3  full-page colour (the slowest case)
// Run: swift scripts/make-speed-test.swift [output.pdf]
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "output/pdf/g2010-speed-test.pdf"
// Resolve first: a bare "test.pdf" has no directory part to create.
let outURL = URL(fileURLWithPath: outPath)
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
var box = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4 in points
guard let ctx = CGContext(outURL as CFURL, mediaBox: &box, nil) else { fatalError("cannot write \(outPath)") }

func text(_ s: String, _ rect: CGRect, size: CGFloat, bold: Bool = false, color: NSColor = .black) {
    let para = NSMutableParagraphStyle(); para.lineSpacing = 2
    let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para]).draw(in: rect)
}

func page(_ body: () -> Void) {
    ctx.beginPDFPage(nil)
    let g = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    body()
    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
}

let lorem = "The quick brown fox jumps over the lazy dog. ทดสอบการพิมพ์ภาษาไทยและภาษาอังกฤษ เอกสารตัวหนังสือสีดำล้วน "
    + "Pack my box with five dozen liquor jugs. 0123456789 "

func header(_ n: Int, _ title: String) {
    text("Print G2010 speed test — page \(n) of 3: \(title)", CGRect(x: 50, y: 790, width: 495, height: 30), size: 14, bold: true)
    text("Mode used: ____________________   Time (first sheet out → last sheet out): ________ s",
         CGRect(x: 50, y: 765, width: 495, height: 20), size: 10)
}

// Page 1: dense black text
page {
    header(1, "black text")
    text(String(repeating: lorem, count: 22), CGRect(x: 50, y: 60, width: 495, height: 690), size: 11)
}

// Page 2: text + colour pictures
page {
    header(2, "text and colour pictures")
    text(String(repeating: lorem, count: 5), CGRect(x: 50, y: 640, width: 495, height: 110), size: 11)
    let colors: [NSColor] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .magenta]
    for (i, c) in colors.enumerated() {
        c.setFill()
        CGRect(x: 50 + CGFloat(i) * 62, y: 540, width: 56, height: 80).fill()
    }
    NSGradient(colors: [.red, .yellow, .green, .cyan, .blue, .magenta, .red])!.draw(in: CGRect(x: 50, y: 440, width: 495, height: 80), angle: 0)
    NSGradient(colors: [.black, .white])!.draw(in: CGRect(x: 50, y: 350, width: 495, height: 70), angle: 0)
    text(String(repeating: lorem, count: 6), CGRect(x: 50, y: 60, width: 495, height: 270), size: 11)
}

// Page 3: full-page colour
page {
    NSGradient(colors: [NSColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1), NSColor(red: 0.9, green: 0.2, blue: 0.4, alpha: 1),
                        NSColor(red: 1.0, green: 0.8, blue: 0.1, alpha: 1)])!.draw(in: box, angle: 60)
    NSColor.white.withAlphaComponent(0.85).setFill()
    CGRect(x: 40, y: 750, width: 515, height: 70).fill()
    header(3, "full-page colour")
}

ctx.closePDF()
print("wrote \(outPath)")
