// pdf-tool: split a PDF into one single-page PDF per page (p1.pdf, p2.pdf, ...).
// Used by scripts/g2010-print so every page can be sent as its own print job,
// in any order. Prints the page count on stdout.
import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count == 4, args[1] == "split" else {
    FileHandle.standardError.write(Data("usage: pdf-tool split in.pdf outdir\n".utf8))
    exit(2)
}
guard let doc = PDFDocument(url: URL(fileURLWithPath: args[2])), doc.pageCount > 0 else {
    FileHandle.standardError.write(Data("cannot read PDF: \(args[2])\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: args[3], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for i in 0..<doc.pageCount {
    guard let page = doc.page(at: i)?.copy() as? PDFPage else { exit(1) }
    let single = PDFDocument()
    single.insert(page, at: 0)
    guard single.write(to: out.appendingPathComponent("p\(i + 1).pdf")) else {
        FileHandle.standardError.write(Data("cannot write page \(i + 1)\n".utf8))
        exit(1)
    }
}
print(doc.pageCount)
