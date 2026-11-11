import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings

/// Scan colour mode; the raw value is what `scanimage --mode` expects.
enum ScanMode: String, CaseIterable, Identifiable {
    case color = "Color", gray = "Gray", lineart = "Lineart"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .color: return "Colour"
        case .gray: return "Gray"
        case .lineart: return "B&W"
        }
    }
}

/// Resolutions the G2010 scanner reports.
enum ScanResolution: Int, CaseIterable, Identifiable {
    case dpi75 = 75, dpi150 = 150, dpi300 = 300, dpi600 = 600
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .dpi75: return "75 dpi (draft)"
        case .dpi150: return "150 dpi"
        case .dpi300: return "300 dpi"
        case .dpi600: return "600 dpi (slow)"
        }
    }
}

/// Area of the glass to scan, in millimetres from the corner. The glass itself is about 216 × 297 mm.
enum ScanPaper: String, CaseIterable, Identifiable {
    case a4 = "A4", a5 = "A5", letter = "Letter", glass = "Whole Glass"
    var id: String { rawValue }
    var sizeMM: (width: String, height: String)? {
        switch self {
        case .a4: return ("210", "297")
        case .a5: return ("148", "210")
        case .letter: return ("215.9", "279.4")
        case .glass: return nil
        }
    }
}

enum ScanFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF", png = "PNG", jpeg = "JPEG"
    var id: String { rawValue }
    var type: UTType {
        switch self {
        case .pdf: return .pdf
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue.lowercased() }
}

enum ScanState: Equatable {
    case idle
    case waitingForPrinter
    case scanning
    case failed(String)
}

struct ScannedPage: Identifiable {
    let id = UUID()
    /// Uncompressed TIFF straight from the scanner, kept in a temporary folder until saved or discarded.
    let url: URL
    let dpi: Int
    let mode: ScanMode
    let thumbnail: NSImage
}

// MARK: - scanimage

/// The scanner side of `Engine`: SANE's `scanimage`, built by scripts/build-sane.sh and bundled in
/// the app next to the Gutenprint files (G2010_ROOT points at a repo checkout instead).
enum ScanEngine {
    static var directory: String { Engine.root + "/build/sane" }
    static var scanimage: String { directory + "/bin/scanimage" }
    static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: scanimage) }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["SANE_CONFIG_DIR"] = directory + "/etc"
        return env
    }
}

/// One run of scanimage that can be stopped from outside.
final class ScanProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var wasCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        process?.terminate()
    }

    func run(_ args: [String]) async -> ProcessResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ScanEngine.scanimage)
            p.arguments = args
            p.environment = ScanEngine.environment
            let err = Pipe(), out = Pipe()
            p.standardError = err
            p.standardOutput = out
            p.terminationHandler = { proc in
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: ProcessResult(status: proc.terminationStatus, stdout: o, stderr: e))
            }
            lock.lock()
            if cancelled {
                lock.unlock()
                cont.resume(returning: ProcessResult(status: 143, stdout: "", stderr: ""))
                return
            }
            do {
                try p.run()
                process = p
                lock.unlock()
            } catch {
                lock.unlock()
                cont.resume(returning: ProcessResult(status: 127, stdout: "", stderr: "\(error)"))
            }
        }
    }
}

// MARK: - Images

enum ScanImage {
    /// The scan at its full resolution, sized in pixels (used by the large preview).
    static func fullSize(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// A reduced copy for the screen; the full-size scan stays on disk.
    static func downsampled(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct ScanExportError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ScanExport {
    /// Writes the pages: one PDF with a page per scan, or one image file per scan. Several images are
    /// numbered ("Scan 1.png", "Scan 2.png"). Returns the files written.
    static func write(_ pages: [ScannedPage], as format: ScanFormat, to url: URL) throws -> [URL] {
        if format == .pdf {
            try writePDF(pages, to: url)
            return [url]
        }
        let ext = url.pathExtension.isEmpty ? format.fileExtension : url.pathExtension
        let base = url.deletingPathExtension()
        var targets: [URL] = []
        for (i, _) in pages.enumerated() {
            if pages.count == 1 {
                targets.append(base.appendingPathExtension(ext))
            } else {
                targets.append(base.deletingLastPathComponent()
                    .appendingPathComponent("\(base.lastPathComponent) \(i + 1)").appendingPathExtension(ext))
            }
        }
        if pages.count > 1, let existing = targets.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            throw ScanExportError(message: "\(existing.lastPathComponent) already exists. Choose another name.")
        }
        for (page, target) in zip(pages, targets) {
            try writeImage(page, type: format.type, to: target)
        }
        return targets
    }

    private static func writeImage(_ page: ScannedPage, type: UTType, to url: URL) throws {
        guard let src = CGImageSourceCreateWithURL(page.url as CFURL, nil),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ScanExportError(message: "Could not create \(url.lastPathComponent).")
        }
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: page.dpi, kCGImagePropertyDPIHeight: page.dpi]
        if type == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = 0.85 }
        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ScanExportError(message: "Could not write \(url.lastPathComponent).")
        }
    }

    private static func writePDF(_ pages: [ScannedPage], to url: URL) throws {
        var first = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &first, nil) else {
            throw ScanExportError(message: "Could not create \(url.lastPathComponent).")
        }
        for page in pages {
            guard let image = pdfImage(for: page) else {
                context.closePDF()
                throw ScanExportError(message: "Could not read a scanned page.")
            }
            // One PDF page the size of the paper that was scanned.
            var box = CGRect(x: 0, y: 0,
                             width: CGFloat(image.width) * 72 / CGFloat(page.dpi),
                             height: CGFloat(image.height) * 72 / CGFloat(page.dpi))
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)]
            context.beginPDFPage(info as CFDictionary)
            context.draw(image, in: box)
            context.endPDFPage()
        }
        context.closePDF()
    }

    /// Colour and gray pages are stored as JPEG inside the PDF (a raw A4 scan at 300 dpi is about
    /// 26 MB); black and white pages stay lossless so text does not get fuzzy.
    private static func pdfImage(for page: ScannedPage) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(page.url as CFURL, nil) else { return nil }
        if page.mode == .lineart { return CGImageSourceCreateImageAtIndex(src, 0, nil) }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(dest, src, 0,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest),
              let jpeg = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(jpeg, 0, nil)
    }
}

// MARK: - Model

@MainActor
final class ScanModel: ObservableObject {
    static let shared = ScanModel()

    /// Settings, remembered between launches.
    @Published var mode: ScanMode = ScanMode(rawValue: UserDefaults.standard.string(forKey: "scanMode") ?? "") ?? .color {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "scanMode") }
    }
    @Published var resolution: ScanResolution = ScanResolution(rawValue: UserDefaults.standard.integer(forKey: "scanResolution")) ?? .dpi300 {
        didSet { UserDefaults.standard.set(resolution.rawValue, forKey: "scanResolution") }
    }
    @Published var paper: ScanPaper = ScanPaper(rawValue: UserDefaults.standard.string(forKey: "scanPaper") ?? "") ?? .a4 {
        didSet { UserDefaults.standard.set(paper.rawValue, forKey: "scanPaper") }
    }
    @Published var format: ScanFormat = ScanFormat(rawValue: UserDefaults.standard.string(forKey: "scanFormat") ?? "") ?? .pdf {
        didSet { UserDefaults.standard.set(format.rawValue, forKey: "scanFormat") }
    }

    @Published private(set) var pages: [ScannedPage] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var preview: NSImage?
    @Published private(set) var state: ScanState = .idle
    /// Files written by the last Save, for "Show in Finder".
    @Published private(set) var lastSaved: [URL] = []

    private var task: Task<Void, Never>?
    private var process: ScanProcess?
    private var folder: URL?

    /// The scanner is in use right now; printing waits for this to end (see PrintModel.drain).
    var scanning: Bool { state == .scanning }
    var busy: Bool { state == .scanning || state == .waitingForPrinter }

    var selectedPage: ScannedPage? { pages.first { $0.id == selectedID } }

    // MARK: Scanning

    func scanPage() {
        guard !busy else { return }
        guard ScanEngine.isAvailable else {
            state = .failed("The scanner tools are missing from this copy of the app.")
            return
        }
        lastSaved = []
        let mode = mode, dpi = resolution.rawValue, paper = paper
        task = Task { await self.run(mode: mode, dpi: dpi, paper: paper) }
    }

    /// Stops a scan in progress, or the wait for the printer.
    func cancel() {
        task?.cancel()
        process?.cancel()
    }

    private func run(mode: ScanMode, dpi: Int, paper: ScanPaper) async {
        // The printer and scanner share one USB cable, so wait until printing is over. Both checks
        // below and "state = .scanning" happen without a suspension in between, and the print queue
        // does the same in reverse, so the two cannot start at once.
        while true {
            if Task.isCancelled { state = .idle; return }
            if PrintModel.shared.busy {
                state = .waitingForPrinter
            } else {
                let printer = await Engine.printerStatus()
                if !PrintModel.shared.busy && printer != .printing { break }
                state = .waitingForPrinter
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        state = .scanning

        let out = scanFolder().appendingPathComponent("page-\(UUID().uuidString).tiff")
        var args = ["--mode", mode.rawValue, "--resolution", String(dpi), "--format=tiff", "--output-file", out.path]
        if let size = paper.sizeMM { args += ["-x", size.width, "-y", size.height] }

        let proc = ScanProcess()
        process = proc
        let result = await proc.run(args)
        process = nil

        if proc.wasCancelled || Task.isCancelled {
            try? FileManager.default.removeItem(at: out)
            state = .idle
            return
        }
        guard result.status == 0, FileManager.default.fileExists(atPath: out.path) else {
            try? FileManager.default.removeItem(at: out)
            state = .failed(Self.explain(result.stderr))
            return
        }
        let thumb = await Task.detached { ScanImage.downsampled(out, maxPixel: 220) }.value
        guard let thumb else {
            try? FileManager.default.removeItem(at: out)
            state = .failed("The scan finished but the picture could not be read.")
            return
        }
        let page = ScannedPage(url: out, dpi: dpi, mode: mode, thumbnail: thumb)
        pages.append(page)
        select(page.id)
        state = .idle
    }

    private static func explain(_ stderr: String) -> String {
        if stderr.contains("No scanners were identified") || stderr.contains("open of device") {
            return "Scanner not found. Turn the printer on and check the USB cable."
        }
        let lines = stderr.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return lines.isEmpty ? "The scan failed." : "The scan failed.\n" + lines.suffix(3).joined(separator: "\n")
    }

    private func scanFolder() -> URL {
        if let folder { return folder }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PrintG2010-scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = url
        return url
    }

    // MARK: Pages

    func select(_ id: UUID?) {
        selectedID = id
        guard let page = selectedPage else { preview = nil; return }
        let url = page.url, wanted = page.id
        Task {
            let image = await Task.detached { ScanImage.downsampled(url, maxPixel: 1100) }.value
            if selectedID == wanted { preview = image }
        }
    }

    func delete(_ id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: pages[i].url)
        pages.remove(at: i)
        if selectedID == id { select(pages.isEmpty ? nil : pages[min(i, pages.count - 1)].id) }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = pages.firstIndex(where: { $0.id == id }), pages.indices.contains(i + offset) else { return }
        pages.swapAt(i, i + offset)
    }

    /// Removes every page and its temporary file.
    func discardAll() {
        pages = []
        select(nil)
        lastSaved = []
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        if case .failed = state { state = .idle }
    }

    // MARK: Saving

    var defaultName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return "Scan " + f.string(from: Date())
    }

    func save() {
        guard !pages.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Save Scan"
        panel.nameFieldStringValue = defaultName + "." + format.fileExtension
        panel.allowedContentTypes = [format.type]
        panel.canCreateDirectories = true
        if format != .pdf && pages.count > 1 {
            panel.message = "Each page is saved as its own file, numbered after this name."
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let pages = pages, format = format
        Task {
            do {
                let written = try await Task.detached { try ScanExport.write(pages, as: format, to: url) }.value
                lastSaved = written
                if case .failed = state { state = .idle }
            } catch {
                state = .failed("Could not save the scan. \(error.localizedDescription)")
            }
        }
    }

    /// Headless check (`--scan-selftest <folder> [mode] [dpi]`): scan one page and save it in every format.
    func selfTest(into folder: URL, mode: ScanMode, dpi: Int) async {
        self.mode = mode
        resolution = ScanResolution(rawValue: dpi) ?? .dpi300
        scanPage()
        await task?.value
        guard state == .idle, pages.count == 1 else {
            Swift.print("scan-selftest: failed", state, "pages:", pages.count)
            return
        }
        for format in ScanFormat.allCases {
            let url = folder.appendingPathComponent("selftest-\(mode.rawValue)-\(dpi).\(format.fileExtension)")
            do {
                let written = try ScanExport.write(pages, as: format, to: url)
                let size = (try? written[0].resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                Swift.print("scan-selftest:", format.rawValue, written[0].path, size, "bytes")
            } catch {
                Swift.print("scan-selftest:", format.rawValue, "failed:", error.localizedDescription)
            }
        }
        discardAll()
    }

    func revealSaved() {
        NSWorkspace.shared.activateFileViewerSelecting(lastSaved)
    }
}
