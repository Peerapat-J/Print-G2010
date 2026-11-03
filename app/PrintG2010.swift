// Print G2010: a one-window front end for scripts/g2010-print.
// Pick or drop files, set the number of copies, press print, watch the status.
// Built by scripts/build-app.sh; the repo path is stored in Info.plist (G2010Root).

import SwiftUI
import AppKit
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

/// Progress of one run of scripts/g2010-print, fed by its "@@" lines.
@MainActor
final class FileRun {
    var result: ProcessResult?
    var jobs: [String] = []
    var total = 0
    var sent = 0
    var preparing = true

    func handle(_ parts: [String]) {
        switch parts.first {
        case "total": total = Int(parts.dropFirst().first ?? "") ?? 0
        case "job": if let id = parts.dropFirst().first, !id.isEmpty { jobs.append(id) }
        case "page": sent = Int((parts.dropFirst().first ?? "").split(separator: "/").first ?? "") ?? sent
        case "convert", "prepare": preparing = true
        default: break
        }
    }
}

@MainActor
final class PrintModel: ObservableObject {
    static let shared = PrintModel()

    @Published var files: [URL] = []
    @Published var copiesText = "1"
    @Published var state: PrintState = .idle
    @Published var printer: PrinterStatus = .checking
    /// The G2010 puts pages out face up, so sending the last page first leaves the stack in order.
    @Published var reverseOrder: Bool = UserDefaults.standard.object(forKey: "reverseOrder") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reverseOrder, forKey: "reverseOrder") }
    }

    /// nil unless the field holds a whole number from 1 to 99.
    var copies: Int? {
        guard let n = Int(copiesText), (1...99).contains(n) else { return nil }
        return n
    }

    var busy: Bool {
        if case .working = state { return true }
        return false
    }

    var canPrint: Bool {
        !files.isEmpty && !busy && copies != nil && printer.canAcceptJobs
    }

    func monitorPrinter() async {
        while !Task.isCancelled {
            printer = await Engine.printerStatus()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    func add(_ urls: [URL]) {
        guard !busy else { return }
        var rejected: [String] = []
        for url in urls where url.isFileURL {
            if Engine.officeExts.contains(url.pathExtension.lowercased()) {
                rejected.append(url.lastPathComponent)
            } else if !files.contains(url) {
                files.append(url)
            }
        }
        if rejected.isEmpty {
            if case .failed = state { state = .idle }
        } else {
            state = .failed("พิมพ์ไฟล์ Word/Pages/Office โดยตรงไม่ได้: " + rejected.joined(separator: ", ")
                            + "\nให้ Export เป็น PDF ก่อน (File > Export As > PDF)")
        }
    }

    func remove(_ url: URL) {
        guard !busy else { return }
        files.removeAll { $0 == url }
    }

    func clear() {
        guard !busy else { return }
        files = []
        state = .idle
    }

    func print() {
        guard !files.isEmpty, !busy, let copies = self.copies else { return }
        let todo = files
        state = .working("กำลังเริ่ม…")
        let reverse = reverseOrder
        Task { await self.runAll(todo, copies: copies, reverse: reverse) }
    }

    private func runAll(_ todo: [URL], copies: Int, reverse: Bool) async {
        let began = Date()
        for (i, file) in todo.enumerated() {
            let prefix = todo.count > 1 ? "ไฟล์ \(i + 1)/\(todo.count) · " : ""
            if !(await runOne(file, copies: copies, reverse: reverse, prefix: prefix)) { return }
        }
        let took = Int(Date().timeIntervalSince(began))
        let summary = "\(todo.count) ไฟล์ × \(copies) ชุด"
        state = .done(Engine.dryRun
                      ? "ทดสอบแปลงไฟล์เรียบร้อย (\(summary)) ยังไม่ได้ส่งไปเครื่องพิมพ์"
                      : "พิมพ์เสร็จแล้ว (\(summary)) ใช้เวลา \(took) วินาที")
    }

    /// Runs the script and, while it is converting and sending pages, follows the CUPS queue
    /// to count how many pages the printer has taken. Returns false after showing an error.
    private func runOne(_ file: URL, copies: Int, reverse: Bool, prefix: String) async -> Bool {
        let name = file.lastPathComponent
        var args = ["-n", String(copies)]
        if !reverse { args.append("--no-reverse") }
        if Engine.dryRun { args.append("--dry-run") }
        args.append(file.path)

        let run = FileRun()
        state = .working("\(prefix)กำลังเตรียมไฟล์ \(name)")
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
                state = .failed("พิมพ์ \(name) ไม่สำเร็จ\n\(detail)")
                return false
            }
            if run.result != nil && queued == 0 {
                return true
            }
            if run.result != nil && Date().timeIntervalSince(lastProgress) > 180 {
                state = .failed("\(name): งานค้างอยู่ในคิวนานเกินไป ตรวจที่เครื่องพิมพ์ว่าเปิดอยู่ มีกระดาษ และไม่มีไฟเตือน")
                return false
            }

            let elapsed = Int(Date().timeIntervalSince(start))
            if run.jobs.isEmpty {
                state = .working("\(prefix)กำลังเตรียมไฟล์ \(name) (\(elapsed) วินาที)")
            } else {
                state = .working("\(prefix)\(name) — ส่งแล้ว \(run.sent)/\(run.total) หน้า · "
                                 + "พิมพ์แล้ว \(printed)/\(run.total) หน้า (\(elapsed) วินาที)")
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

// MARK: - Views

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
                Button("เพิ่มไฟล์…") { chooseFiles() }
                    .disabled(model.busy)
                if !model.files.isEmpty {
                    Button("ล้างรายการ") { model.clear() }
                        .disabled(model.busy)
                }
                Spacer()
                Text("จำนวนชุด")
                TextField("", text: $model.copiesText)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .disabled(model.busy)
                    .onChange(of: model.copiesText) { _, v in
                        // digits only, at most two of them
                        let clean = String(v.filter { $0.isASCII && $0.isNumber }.prefix(2))
                        if clean != v { model.copiesText = clean }
                    }
                Stepper("", value: Binding(get: { model.copies ?? 1 },
                                           set: { model.copiesText = String($0) }),
                        in: 1...99)
                    .labelsHidden()
                    .disabled(model.busy)
            }
            if model.copies == nil {
                Text("กรอกจำนวนชุดเป็นตัวเลข 1–99")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Toggle("พิมพ์จากหน้าสุดท้ายก่อน (กองกระดาษที่ออกมาเรียงหน้า 1 อยู่บนสุด)", isOn: $model.reverseOrder)
                .toggleStyle(.checkbox)
                .disabled(model.busy)

            Button {
                model.print()
            } label: {
                Text("พิมพ์").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canPrint)

            statusView
        }
        .padding(20)
        .task { await model.monitorPrinter() }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 460)
    }

    @ViewBuilder private var printerBadge: some View {
        let (color, text): (Color, String) = {
            switch model.printer {
            case .checking: return (.gray, "กำลังตรวจสอบเครื่องพิมพ์…")
            case .ready: return (.green, "เครื่องพิมพ์พร้อม")
            case .printing: return (.orange, "เครื่องพิมพ์กำลังทำงาน")
            case .offline: return (.red, "ไม่พบเครื่องพิมพ์ — เปิดเครื่องและตรวจสาย USB")
            case .stopped: return (.red, "คิวพิมพ์ถูกหยุด — ตรวจกระดาษ/ไฟเตือนที่เครื่อง")
            case .missingQueue: return (.red, "ไม่พบคิวพิมพ์ \(Engine.queue) ในระบบ")
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
                    Text("ลากไฟล์ PDF หรือรูปภาพมาวางที่นี่")
                    Text("หรือกด “เพิ่มไฟล์…”").foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(model.files, id: \.self) { url in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            Button { model.remove(url) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.busy)
                            .help("เอาออกจากรายการ")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .padding(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            guard !model.busy else { return false }
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
                Text(model.files.isEmpty ? "ยังไม่ได้เลือกไฟล์"
                     : model.printer.canAcceptJobs ? "พร้อมพิมพ์ กดปุ่ม “พิมพ์”"
                     : "รอเครื่องพิมพ์พร้อมก่อนจึงจะพิมพ์ได้")
                    .foregroundStyle(.secondary)
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

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "เลือกไฟล์ที่จะพิมพ์"
        panel.message = "PDF, รูปภาพ หรือไฟล์ข้อความ (เลือกได้หลายไฟล์)"
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
        // Headless check: print the given file through the same code path and report the end state.
        let model = PrintModel.shared
        model.add([URL(fileURLWithPath: args[i + 1])])
        model.print()
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
            MainActor.assumeIsolated {
                if !model.busy {
                    t.invalidate()
                    Swift.print("selftest:", model.state)
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
        .defaultSize(width: 520, height: 560)
        .windowResizability(.contentMinSize)
    }
}
