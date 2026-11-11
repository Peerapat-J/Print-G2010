// Print G2010: a one-window front end for scripts/g2010-print.
// Pick or drop files, set copies and pages for each file, press print, watch the status.
// Built by the Xcode project (see project.yml); the helpers it needs are bundled in the app.

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
    /// Directory with scripts/g2010-print and build/ (Gutenprint, PPD, pdf-tool). The Xcode build
    /// copies them into the app; G2010_ROOT points at a repo checkout instead.
    static let root: String = {
        if let override = ProcessInfo.processInfo.environment["G2010_ROOT"] { return override }
        return (Bundle.main.resourcePath ?? "") + "/g2010"
    }()
    static let env = ProcessInfo.processInfo.environment
    static let dryRun = env["G2010_DRY_RUN"] == "1"
    /// The CUPS queue used for printing. Found with `lpstat -v` (see `refreshQueue`);
    /// G2010_QUEUE overrides it.
    static var queue = env["G2010_QUEUE"] ?? "Canon_G2010_series"
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
    /// The queue whose device is the G2010's USB port, whatever the user called it:
    /// "device for Canon_G2010_series: usb://Canon/G2010%20series?serial=..."
    static func findQueue() async -> String? {
        let r = await run("/usr/bin/lpstat", ["-v"])
        for line in r.stdout.split(separator: "\n") where line.hasPrefix("device for ") && line.contains("G2010") {
            let rest = line.dropFirst("device for ".count)
            if let colon = rest.firstIndex(of: ":") { return String(rest[..<colon]) }
        }
        return nil
    }

    /// Updates `queue`; false when there is no queue for the G2010 (printer not added yet).
    static func refreshQueue() async -> Bool {
        if env["G2010_QUEUE"] != nil { return true }
        guard let found = await findQueue() else { return false }
        queue = found
        return true
    }

    /// Combines "is the G2010 on the USB bus" (printer on and cable fine) with the CUPS queue state.
    static func printerStatus() async -> PrinterStatus {
        guard await refreshQueue() else { return .missingQueue }
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

/// Colour or black-ink-only printing (g2010-print --color). Grayscale is faster and uses no colour ink.
enum ColorMode: String, CaseIterable, Identifiable {
    case color, gray
    var id: String { rawValue }
    var label: String { self == .color ? "Colour" : "Grayscale" }
}

/// Print resolution (g2010-print --dpi). 300 dpi needs fewer head passes, so it prints faster.
enum Resolution: String, CaseIterable, Identifiable {
    case dpi600 = "600", dpi300 = "300"
    var id: String { rawValue }
    var label: String { self == .dpi600 ? "600 dpi (best)" : "300 dpi (faster)" }
}

struct PrintJob {
    var url: URL
    var copies: Int
    var reverse: Bool
    var color: ColorMode
    var resolution: Resolution
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

/// What one file is printed with: how many copies and which pages. Kept per file, and kept after
/// the file has been printed so it can be printed again the same way.
struct FileSettings: Equatable {
    var copies = 1
    var pageMode = PageMode.all
    var pageSpec = ""
    /// Known for PDFs only.
    var pageCount: Int?

    var pagesError: String? {
        switch pageMode {
        case .custom: return pageSpecError(pageSpec, pageCount: pageCount)
        case .even: return (pageCount ?? 2) < 2 ? "This document has no even pages" : nil
        default: return nil
        }
    }

    /// What g2010-print --pages accepts; empty for every page.
    var pagesArgument: String {
        switch pageMode {
        case .all: return ""
        case .odd: return "odd"
        case .even: return "even"
        case .custom: return pageSpec.filter { !$0.isWhitespace }
        }
    }

    var isDefault: Bool { copies == 1 && pageMode == .all }

    /// Shown in the badge on the file's row, e.g. "2 copies · Pages 3-5".
    var summary: String {
        let copiesLabel = copies == 1 ? "1 copy" : "\(copies) copies"
        let pagesLabel: String
        switch pageMode {
        case .all: pagesLabel = "All pages"
        case .odd: pagesLabel = "Odd pages"
        case .even: pagesLabel = "Even pages"
        case .custom:
            let spec = pagesArgument.replacingOccurrences(of: ",", with: ", ")
            pagesLabel = (spec.contains(",") || spec.contains("-") ? "Pages " : "Page ") + spec
        }
        return "\(copiesLabel) · \(pagesLabel)"
    }
}

@MainActor
final class PrintModel: ObservableObject {
    static let shared = PrintModel()

    @Published var files: [URL] = []
    @Published var selected: Set<URL> = []
    @Published var fileStatus: [URL: FileStatus] = [:]
    @Published var settings: [URL: FileSettings] = [:]
    @Published var state: PrintState = .idle
    @Published var printer: PrinterStatus = .checking
    @Published private(set) var queue: [PrintJob] = []
    @Published private(set) var running = false
    /// The G2010 puts pages out face up, so sending the last page first leaves the stack in order.
    @Published var reverseOrder: Bool = UserDefaults.standard.object(forKey: "reverseOrder") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reverseOrder, forKey: "reverseOrder") }
    }

    /// Quality settings, remembered between launches; each queued job keeps the values it was added with.
    @Published var colorMode: ColorMode = ColorMode(rawValue: UserDefaults.standard.string(forKey: "colorMode") ?? "") ?? .color {
        didSet { UserDefaults.standard.set(colorMode.rawValue, forKey: "colorMode") }
    }
    @Published var resolution: Resolution = Resolution(rawValue: UserDefaults.standard.string(forKey: "resolution") ?? "") ?? .dpi600 {
        didSet { UserDefaults.standard.set(resolution.rawValue, forKey: "resolution") }
    }

    var busy: Bool { running }

    func status(_ url: URL) -> FileStatus { fileStatus[url] ?? .waiting }
    func settings(for url: URL) -> FileSettings { settings[url] ?? FileSettings() }

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
                let pageCount = url.pathExtension.lowercased() == "pdf" ? PDFDocument(url: url)?.pageCount : nil
                settings[url] = FileSettings(pageCount: pageCount)
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
        settings[url] = nil
    }

    func clear() {
        guard !running else { return }
        files = []
        selected = []
        fileStatus = [:]
        settings = [:]
        state = .idle
    }

    /// The print button: every ticked file, top to bottom, each with its own copies and pages.
    func printSelected() {
        enqueue(selectedFiles)
    }

    /// Adds files to the print queue with their own settings; files already queued or printing are skipped.
    func enqueue(_ urls: [URL]) {
        let reverse = reverseOrder
        let color = colorMode, resolution = resolution
        let new = urls.filter { !status($0).isActive }
        guard !new.isEmpty else { return }
        for url in new {
            let s = settings(for: url)
            fileStatus[url] = .queued
            queue.append(PrintJob(url: url, copies: s.copies, reverse: reverse, color: color,
                                  resolution: resolution, pages: s.pagesArgument))
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
        _ = await Engine.refreshQueue()
        var args = ["-q", Engine.queue, "-n", String(job.copies)]
        if !job.reverse { args.append("--no-reverse") }
        args += ["--color", job.color.rawValue, "--dpi", job.resolution.rawValue]
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
    @State private var editing = false
    @State private var draft = FileSettings()
    @State private var rowCopies = "1"
    @State private var hovering = false

    var body: some View {
        let status = model.status(url)
        let settings = model.settings(for: url)
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { model.selected.contains(url) },
                                     set: { model.setSelected(url, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(status.isActive)
                .help("Tick the files to print with “Print Selected”")
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 24, height: 24)
                .handCursor(model.files.count > 1)
            VStack(alignment: .leading, spacing: 3) {
                // First line: the name, which can be grabbed to reorder (open hand), and the remove button.
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                    .handCursor(model.files.count > 1)
                    Button { model.remove(url) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled({ if case .working = status { return true } else { return false } }())
                    .help("Remove from list")
                }
                // Second line: what will be printed, how it is going, and where the file is.
                HStack(spacing: 6) {
                    settingsBadge(settings, locked: status.isActive)
                    statusBadge(status)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }

    private func openEditor() {
        draft = model.settings(for: url)
        rowCopies = String(draft.copies)
        editing = true
    }

    /// Copies and pages for this file. A button that opens the editor; changed values show in the accent colour.
    private func settingsBadge(_ s: FileSettings, locked: Bool) -> some View {
        Button { openEditor() } label: {
            HStack(spacing: 4) {
                Text(s.summary).lineLimit(1)
                if !locked { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(s.isDefault ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((s.isDefault ? Color.secondary : Color.accentColor).opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .layoutPriority(1)
        .help(locked ? "This file is already in the print queue" : "Change copies and pages")
        .popover(isPresented: $editing, arrowEdge: .bottom) { editor }
    }

    private var editor: some View {
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
                Picker("", selection: $draft.pageMode) {
                    ForEach(PageMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            if draft.pageMode == .custom {
                TextField("e.g. 1, 3, 5-9 or 8", text: $draft.pageSpec)
                    .textFieldStyle(.roundedBorder)
            }
            if let error = draft.pagesError, draft.pageMode != .custom || !draft.pageSpec.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let n = draft.pageCount {
                Text("This document has \(n) \(n == 1 ? "page" : "pages").")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { editing = false }
                Button("Done") {
                    if let n = parseCopies(rowCopies), draft.pagesError == nil {
                        draft.copies = n
                        model.settings[url] = draft
                        editing = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(invalid)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var invalid: Bool { parseCopies(rowCopies) == nil || draft.pagesError != nil }

    @ViewBuilder private func statusBadge(_ status: FileStatus) -> some View {
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
            }
            HStack {
                Picker("Colour", selection: $model.colorMode) {
                    ForEach(ColorMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Resolution", selection: $model.resolution) {
                    ForEach(Resolution.allCases) { Text($0.label).tag($0) }
                }
            }
            .help("Grayscale and 300 dpi print faster. Applies to files added to the queue from now on.")
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
            .disabled(model.selectedFiles.isEmpty || !model.printer.canAcceptJobs)

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
            case .missingQueue: return (.red, "No print queue for the G2010 — add the printer in System Settings")
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
        if model.selectedFiles.isEmpty { return "Tick the files to print" }
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
        model.enqueue([urls[0]])
        if urls.count > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    model.enqueue(Array(urls.dropFirst()))
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
