// Print G2010: a one-window front end for scripts/g2010-print.
// Pick or drop files, set the number of copies, press print, watch the status.
// Built by scripts/build-app.sh; the repo path is stored in Info.plist (G2010Root).

import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Running the print script

final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var text = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(_ onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func append(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
        lock.lock()
        text += chunk
        pending += chunk
        var lines: [String] = []
        while let nl = pending.firstIndex(of: "\n") {
            lines.append(String(pending[..<nl]))
            pending.removeSubrange(...nl)
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func flush() {
        lock.lock()
        let rest = pending
        pending = ""
        lock.unlock()
        if !rest.isEmpty { onLine?(rest) }
    }

    var all: String {
        lock.lock(); defer { lock.unlock() }
        return text
    }
}

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

enum Engine {
    static let root = (Bundle.main.object(forInfoDictionaryKey: "G2010Root") as? String) ?? ""
    static let env = ProcessInfo.processInfo.environment
    static let dryRun = env["G2010_DRY_RUN"] == "1"
    static let queue = env["G2010_QUEUE"] ?? "Canon_G2010_series"
    static let script = root + "/scripts/g2010-print"
    static let officeExts: Set<String> = ["docx", "doc", "pages", "xlsx", "pptx", "key", "numbers"]

    static func run(_ exe: String, _ args: [String],
                    onStderrLine: (@Sendable (String) -> Void)? = nil) async -> ProcessResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            var environment = ProcessInfo.processInfo.environment
            environment["USER"] = NSUserName()
            p.environment = environment
            let errPipe = Pipe(), outPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = outPipe
            let errBuf = LineBuffer(onStderrLine)
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { errBuf.append(d) }
            }
            p.terminationHandler = { proc in
                errPipe.fileHandleForReading.readabilityHandler = nil
                errBuf.append(errPipe.fileHandleForReading.readDataToEndOfFile())
                errBuf.flush()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: ProcessResult(status: proc.terminationStatus, stdout: out, stderr: errBuf.all))
            }
            do { try p.run() } catch {
                cont.resume(returning: ProcessResult(status: 127, stdout: "", stderr: "\(error)"))
            }
        }
    }

    /// How many of the given CUPS jobs are still waiting in the queue.
    static func queuedCount(of ids: [String]) async -> Int {
        let r = await run("/usr/bin/lpstat", ["-o", queue])
        let queued = Set(r.stdout.split(separator: "\n").compactMap { $0.split(separator: " ").first.map(String.init) })
        return ids.filter { queued.contains($0) }.count
    }
}

enum PrinterStatus: Equatable {
    case checking
    case ready
    case printing
    case offline
    case stopped
    case missingQueue

    var canAcceptJobs: Bool { self == .ready || self == .printing }
}

extension Engine {
    /// Combines "is the G2010 on the USB bus" (printer on and cable fine) with the CUPS queue state.
    static func printerStatus() async -> PrinterStatus {
        let q = await run("/usr/bin/lpstat", ["-p", queue])
        if q.status != 0 { return .missingQueue }
        let usb = await run("/usr/sbin/ioreg", ["-p", "IOUSB", "-w0"])
        if !usb.stdout.contains("G2010") { return .offline }
        let first = q.stdout.split(separator: "\n").first.map(String.init) ?? ""
        if first.contains("disabled") { return .stopped }
        if first.contains("now printing") { return .printing }
        return .ready
    }
}

// MARK: - Model

enum PrintState: Equatable {
    case idle
    case working(String)
    case done(String)
    case failed(String)
}

/// Per-file badge in the list.
enum FileStatus: Equatable {
    case waiting
    case queued
    case working(String)
    case done
    case failed

    var isActive: Bool {
        switch self {
        case .queued, .working: return true
        default: return false
        }
    }
}

struct PrintJob {
    var url: URL
    var copies: Int
    var reverse: Bool
    /// Empty for every page, otherwise what g2010-print --pages accepts.
    var pages: String
}

/// Progress of one run of scripts/g2010-print, fed by its "@@" lines.
@MainActor
final class FileRun {
    var result: ProcessResult?
    var jobs: [String] = []
    var total = 0
    var sent = 0

    func handle(_ parts: [String]) {
        switch parts.first {
        case "total": total = Int(parts.dropFirst().first ?? "") ?? 0
        case "job": if let id = parts.dropFirst().first, !id.isEmpty { jobs.append(id) }
        case "page": sent = Int((parts.dropFirst().first ?? "").split(separator: "/").first ?? "") ?? sent
        default: break
        }
    }
}

/// A whole number from 1 to 99, otherwise nil.
func parseCopies(_ text: String) -> Int? {
    guard let n = Int(text), (1...99).contains(n) else { return nil }
    return n
}

enum PageMode: String, CaseIterable, Identifiable {
    case all = "All pages"
    case odd = "Odd pages"
    case even = "Even pages"
    case custom = "Custom…"

    var id: String { rawValue }
}

/// An error message, or nil when `spec` is a usable list such as "1, 3, 5-9".
func pageSpecError(_ spec: String, pageCount: Int?) -> String? {
    let parts = spec.filter { !$0.isWhitespace }.split(separator: ",", omittingEmptySubsequences: false)
    if parts.contains(where: \.isEmpty) { return "Enter pages such as 1, 3, 5-9" }
    for part in parts {
        let nums = part.split(separator: "-", omittingEmptySubsequences: false)
        guard nums.count <= 2, nums.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return "“\(part)” is not a page or a range"
        }
        let values = nums.compactMap { Int($0) }
        if values.contains(where: { $0 < 1 }) { return "Pages start at 1" }
        if values.count == 2, values[0] > values[1] { return "“\(part)” is backwards" }
        if let n = pageCount, let top = values.max(), top > n {
            return "Page \(top) does not exist (the document has \(n))"
        }
    }
    return nil
}

@MainActor
final class PrintModel: ObservableObject {
    static let shared = PrintModel()

    @Published var files: [URL] = []
    @Published var selected: Set<URL> = []
    @Published var fileStatus: [URL: FileStatus] = [:]
    @Published var copiesText = "1"
    @Published var state: PrintState = .idle
    @Published var printer: PrinterStatus = .checking
    @Published private(set) var queue: [PrintJob] = []
    @Published private(set) var running = false
    /// The G2010 puts pages out face up, so sending the last page first leaves the stack in order.
    @Published var reverseOrder: Bool = UserDefaults.standard.object(forKey: "reverseOrder") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reverseOrder, forKey: "reverseOrder") }
    }

    var copies: Int? { parseCopies(copiesText) }
    var busy: Bool { running }

    func status(_ url: URL) -> FileStatus { fileStatus[url] ?? .waiting }

    /// Ticked files that are not already queued or printing, in list order.
    var selectedFiles: [URL] {
        files.filter { selected.contains($0) && !status($0).isActive }
    }

    func monitorPrinter() async {
        while !Task.isCancelled {
            printer = await Engine.printerStatus()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    func add(_ urls: [URL]) {
        var rejected: [String] = []
        for url in urls where url.isFileURL {
            if Engine.officeExts.contains(url.pathExtension.lowercased()) {
                rejected.append(url.lastPathComponent)
            } else if !files.contains(url) {
                files.append(url)
                selected.insert(url)
            }
        }
        if rejected.isEmpty {
            if case .failed = state, !running { state = .idle }
        } else if !running {
            state = .failed("Word, Pages and other Office files cannot be printed directly: " + rejected.joined(separator: ", ")
                            + "\nExport them to PDF first (File > Export As > PDF).")
        }
    }

    func setSelected(_ url: URL, _ on: Bool) {
        if on { selected.insert(url) } else { selected.remove(url) }
    }

    /// Reordering the list changes the order "Print Selected" sends the files in.
    func move(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
    }

    /// A file being printed cannot be removed; a queued one is simply taken out of the queue.
    func remove(_ url: URL) {
        if case .working = status(url) { return }
        queue.removeAll { $0.url == url }
        files.removeAll { $0 == url }
        selected.remove(url)
        fileStatus[url] = nil
    }

    func clear() {
        guard !running else { return }
        files = []
        selected = []
        fileStatus = [:]
        state = .idle
    }

    /// Big button: every ticked file, top to bottom, with the copies field.
    func printSelected() {
        guard let copies = self.copies else { return }
        enqueue(selectedFiles, copies: copies)
    }

    /// Adds files to the print queue; files already queued or printing are skipped.
    func enqueue(_ urls: [URL], copies: Int, pages: String = "") {
        let reverse = reverseOrder
        let new = urls.filter { !status($0).isActive }
        guard !new.isEmpty else { return }
        for url in new {
            fileStatus[url] = .queued
            queue.append(PrintJob(url: url, copies: copies, reverse: reverse, pages: pages))
        }
        if !running {
            running = true
            state = .working("Starting…")
            Task { await self.drain() }
        }
    }

    private func drain() async {
        let began = Date()
        var finished = 0
        while !queue.isEmpty {
            let job = queue.removeFirst()
            if await runOne(job) {
                finished += 1
            } else {
                // Something is wrong with the printer or the file: do not keep feeding the queue.
                let dropped = queue.count
                for j in queue { fileStatus[j.url] = .waiting }
                queue = []
                if dropped > 0, case .failed(let msg) = state {
                    state = .failed(msg + "\nCancelled \(dropped) more queued file(s).")
                }
                running = false
                return
            }
        }
        let took = Int(Date().timeIntervalSince(began))
        state = .done(Engine.dryRun
                      ? "Test run finished (\(finished) file(s)); nothing was sent to the printer."
                      : "Finished printing \(finished) file(s) in \(took) s.")
        running = false
    }

    /// Runs the script and, while it converts and sends pages, follows the CUPS queue to count
    /// how many pages the printer has taken. Returns false after showing an error.
    private func runOne(_ job: PrintJob) async -> Bool {
        let file = job.url
        let name = file.lastPathComponent
        var args = ["-n", String(job.copies)]
        if !job.reverse { args.append("--no-reverse") }
        if !job.pages.isEmpty { args += ["--pages", job.pages] }
        if Engine.dryRun { args.append("--dry-run") }
        args.append(file.path)

        let run = FileRun()
        fileStatus[file] = .working("Preparing")
        Task {
            let r = await Engine.run(Engine.script, args) { line in
                guard line.hasPrefix("@@") else { return }
                let parts = line.dropFirst(2).split(separator: " ").map(String.init)
                Task { @MainActor in run.handle(parts) }
            }
            run.result = r
        }

        let start = Date()
        var lastProgress = Date()
        var lastPrinted = 0
        while true {
            let queued = run.jobs.isEmpty ? 0 : await Engine.queuedCount(of: run.jobs)
            let printed = run.jobs.count - queued
            if printed > lastPrinted { lastPrinted = printed; lastProgress = Date() }

            if let r = run.result, r.status != 0 {
                let detail = r.stderr.split(separator: "\n")
                    .filter { !$0.hasPrefix("@@") }.suffix(3).joined(separator: "\n")
                fileStatus[file] = .failed
                state = .failed("Could not print \(name)\n\(detail)")
                return false
            }
            if run.result != nil && queued == 0 {
                fileStatus[file] = .done
                selected.remove(file)   // ticked = still to print
                return true
            }
            if run.result != nil && Date().timeIntervalSince(lastProgress) > 180 {
                fileStatus[file] = .failed
                state = .failed("\(name): the job has been stuck in the queue for too long. Check that the printer is on, has paper and shows no warning light.")
                return false
            }

            let elapsed = Int(Date().timeIntervalSince(start))
            let waiting = queue.isEmpty ? "" : " · \(queue.count) more waiting"
            if run.jobs.isEmpty {
                state = .working("Preparing \(name) (\(elapsed) s)\(waiting)")
            } else {
                fileStatus[file] = .working("Printed \(printed)/\(run.total) pages")
                state = .working("\(name) — sent \(run.sent)/\(run.total) pages · "
                                 + "printed \(printed)/\(run.total) pages (\(elapsed) s)\(waiting)")
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

// MARK: - Views

struct CopiesField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .onChange(of: text) { _, v in
                    // digits only, at most two of them
                    let clean = String(v.filter { $0.isASCII && $0.isNumber }.prefix(2))
                    if clean != v { text = clean }
                }
            Stepper("", value: Binding(get: { parseCopies(text) ?? 1 }, set: { text = String($0) }), in: 1...99)
                .labelsHidden()
        }
    }
}

/// Shows an open hand while the pointer is over the view, to say "you can drag this".
struct HandCursor: ViewModifier {
    var enabled: Bool
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering && enabled && !inside {
                    NSCursor.openHand.push()
                    inside = true
                } else if !hovering && inside {
                    NSCursor.pop()
                    inside = false
                }
            }
            .onDisappear {
                if inside { NSCursor.pop(); inside = false }
            }
    }
}

extension View {
    func handCursor(_ enabled: Bool = true) -> some View { modifier(HandCursor(enabled: enabled)) }
}

struct FileRow: View {
    @ObservedObject var model: PrintModel
    let url: URL
    @State private var askCopies = false
    @State private var rowCopies = "1"
    @State private var pageMode = PageMode.all
    @State private var pageSpec = ""
    @State private var pageCount: Int?
    @State private var hovering = false

    var body: some View {
        let status = model.status(url)
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { model.selected.contains(url) },
                                     set: { model.setSelected(url, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(status.isActive)
                .help("Tick the files to print with “Print Selected”")
            // The part of the row that can be grabbed to reorder; it shows an open hand.
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .handCursor(model.files.count > 1)
            badge(status)
            Button { openPopover() } label: {
                Image(systemName: "printer.fill").foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(status.isActive || !model.printer.canAcceptJobs)
            .help("Print this file")
            .popover(isPresented: $askCopies, arrowEdge: .bottom) { copiesPopover }
            Button { model.remove(url) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled({ if case .working = status { return true } else { return false } }())
            .help("Remove from list")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }

    private func openPopover() {
        rowCopies = "1"
        pageMode = .all
        pageSpec = ""
        pageCount = url.pathExtension.lowercased() == "pdf" ? PDFDocument(url: url)?.pageCount : nil
        askCopies = true
    }

    private var pagesError: String? {
        switch pageMode {
        case .custom: return pageSpecError(pageSpec, pageCount: pageCount)
        case .even: return (pageCount ?? 2) < 2 ? "This document has no even pages" : nil
        default: return nil
        }
    }

    private var pagesArgument: String {
        switch pageMode {
        case .all: return ""
        case .odd: return "odd"
        case .even: return "even"
        case .custom: return pageSpec.filter { !$0.isWhitespace }
        }
    }

    private var copiesPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Copies")
                Spacer()
                CopiesField(text: $rowCopies)
            }
            if parseCopies(rowCopies) == nil {
                Text("Enter a number from 1 to 99").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Text("Pages")
                Spacer()
                Picker("", selection: $pageMode) {
                    ForEach(PageMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            if pageMode == .custom {
                TextField("e.g. 1, 3, 5-9 or 8", text: $pageSpec)
                    .textFieldStyle(.roundedBorder)
            }
            if let error = pagesError, pageMode != .custom || !pageSpec.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let n = pageCount {
                Text("This document has \(n) \(n == 1 ? "page" : "pages").")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { askCopies = false }
                Button("Print") {
                    if let n = parseCopies(rowCopies), pagesError == nil {
                        askCopies = false
                        model.enqueue([url], copies: n, pages: pagesArgument)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(parseCopies(rowCopies) == nil || pagesError != nil)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    @ViewBuilder private func badge(_ status: FileStatus) -> some View {
        switch status {
        case .waiting: EmptyView()
        case .queued: capsule("Queued", .blue)
        case .working(let text): capsule(text, .orange)
        case .done: capsule("✓ Printed", .green)
        case .failed: capsule("Failed", .red)
        }
    }

    private func capsule(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .fixedSize()
    }
}

struct ContentView: View {
    @ObservedObject var model: PrintModel
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "printer.fill").font(.title2)
                Text("Canon G2010").font(.title2.weight(.semibold))
                Spacer()
                printerBadge
            }

            fileArea

            HStack {
                Button("Add Files…") { chooseFiles() }
                if !model.files.isEmpty {
                    Button("Clear List") { model.clear() }
                        .disabled(model.busy)
                }
                Spacer()
                Text("Copies per file")
                CopiesField(text: $model.copiesText)
            }
            .help("Used by “Print Selected”. The printer button on each file asks for its own copies.")
            if model.copies == nil {
                Text("Enter a number from 1 to 99")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Toggle("Print last page first (stack comes out with page 1 on top)", isOn: $model.reverseOrder)
                .toggleStyle(.checkbox)
                .disabled(model.busy)

            Button {
                model.printSelected()
            } label: {
                let n = model.selectedFiles.count
                Text(n > 0 ? "Print Selected (\(n) \(n == 1 ? "file" : "files"))" : "Print Selected")
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedFiles.isEmpty || model.copies == nil || !model.printer.canAcceptJobs)

            statusView
        }
        .padding(20)
        .task { await model.monitorPrinter() }
        .frame(minWidth: 500, idealWidth: 560, minHeight: 460)
    }

    @ViewBuilder private var printerBadge: some View {
        let (color, text): (Color, String) = {
            switch model.printer {
            case .checking: return (.gray, "Checking printer…")
            case .ready: return (.green, "Printer ready")
            case .printing: return (.orange, "Printer busy")
            case .offline: return (.red, "Printer not found — turn it on and check the USB cable")
            case .stopped: return (.red, "Print queue stopped — check paper and warning lights")
            case .missingQueue: return (.red, "Print queue \(Engine.queue) not found")
            }
        }()
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    @ViewBuilder private var fileArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: model.files.isEmpty ? [6] : []))
            if model.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Drop PDF files or images here")
                    Text("or click “Add Files…”").foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(model.files, id: \.self) { url in
                        FileRow(model: model, url: url)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            .listRowSeparator(.hidden)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                // The hover highlight sits the same distance from the top, left and right edges.
                .padding(.vertical, 6)
                .padding(.trailing, -1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { model.add([url]) } }
                }
            }
            return true
        }
    }

    @ViewBuilder private var statusView: some View {
        HStack(alignment: .top, spacing: 10) {
            switch model.state {
            case .idle:
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                Text(idleText).foregroundStyle(.secondary)
            case .working(let msg):
                ProgressView().controlSize(.small)
                Text(msg)
            case .done(let msg):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(msg)
            case .failed(let msg):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(msg).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleText: String {
        if model.files.isEmpty { return "No files yet" }
        if !model.printer.canAcceptJobs { return "Waiting for the printer to be ready" }
        if model.selectedFiles.isEmpty { return "Tick files to print, or use the printer button on a file" }
        return "Ready to print"
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose files to print"
        panel.message = "PDF, images or text files (you can pick several)"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image, .plainText]
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--printer-status") {
            Task { Swift.print("printer:", await Engine.printerStatus()); exit(0) }
            return
        }
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return }
        // Headless check: print the given files through the same code path and report the end state.
        // The first file starts at once, the others are queued one second later (like clicking
        // their own print buttons while the first is still printing).
        let model = PrintModel.shared
        let urls = args[(i + 1)...].map { URL(fileURLWithPath: $0) }
        model.add(urls)
        model.enqueue([urls[0]], copies: 1)
        if urls.count > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    model.enqueue(Array(urls.dropFirst()), copies: 1)
                    Swift.print("queued:", urls.dropFirst().map { model.status($0) })
                }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
            MainActor.assumeIsolated {
                if !model.busy && Date().timeIntervalSinceReferenceDate > 0 && (urls.count == 1 || model.files.allSatisfy { !model.status($0).isActive && model.status($0) != .waiting }) {
                    t.invalidate()
                    Swift.print("selftest:", model.state, urls.map { model.status($0) }, "selected:", model.selected.count)
                    exit(0)
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        PrintModel.shared.add(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PrintG2010App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Print G2010", id: "main") {
            ContentView(model: PrintModel.shared)
        }
        .defaultSize(width: 560, height: 560)
        .windowResizability(.contentMinSize)
    }
}
