import SwiftUI
import UniformTypeIdentifiers

/// The Scan page: settings on the left, the page on the glass in the middle, the pages scanned so far below.
struct ScanView: View {
    @ObservedObject var model: ScanModel
    @Environment(\.openWindow) private var openWindow
    /// The page being dragged in the strip, so the others can make room as it passes over them.
    @State private var draggingPage: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                settings
                    .frame(width: 232)
                    .padding(16)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    previewArea
                    pageStrip
                }
                .padding(16)
            }
            Divider()
            footer
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(minWidth: 660, idealWidth: 720, minHeight: 500, idealHeight: 540)
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Colour").font(.callout).foregroundStyle(.secondary)
                Picker("Colour", selection: $model.mode) {
                    ForEach(ScanMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Resolution").font(.callout).foregroundStyle(.secondary)
                Picker("Resolution", selection: $model.resolution) {
                    ForEach(ScanResolution.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Paper Size").font(.callout).foregroundStyle(.secondary)
                Picker("Paper Size", selection: $model.paper) {
                    ForEach(ScanPaper.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Save As").font(.callout).foregroundStyle(.secondary)
                Picker("Save As", selection: $model.format) {
                    ForEach(ScanFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                if model.format == .pdf {
                    Picker("PDF files", selection: $model.separatePDFs) {
                        Text("One file").tag(false)
                        Text("Each page").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Text(model.savesOneFilePerPage ? "One \(model.format.rawValue) file for each page."
                     : "One PDF with all the pages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Preview and pages

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08))
            if let image = model.preview {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .border(Color.secondary.opacity(0.35), width: 0.5)
                    // On the paper itself, so the buttons sit in the page's corners whatever its shape.
                    .overlay(alignment: .top) { pageTools }
                    .padding(12)
                    .onTapGesture(count: 2) { openWindow(id: "scan-preview") }
            } else if !model.busy {
                VStack(spacing: 6) {
                    Image(systemName: "scanner").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Put the page face down on the glass")
                    Text("then press “Scan Page”").foregroundStyle(.secondary)
                }
            }
            if model.busy {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(model.state == .scanning ? "Scanning…" : "Waiting for the printer to finish…")
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.preview != nil {
                Button { openWindow(id: "scan-preview") } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .padding(7)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(10)
                .help("View the page larger (or double-click it)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Buttons on the corners of the page shown: turn it left or right (top left), and a trash can that
    /// asks before deleting (top right).
    @ViewBuilder private var pageTools: some View {
        if let page = model.selectedPage {
            HStack(spacing: 8) {
                circleButton("rotate.left", help: "Turn the page left", label: "Turn page left") {
                    model.rotate(page.id, clockwise: false)
                }
                circleButton("rotate.right", help: "Turn the page right", label: "Turn page right") {
                    model.rotate(page.id, clockwise: true)
                }
                Spacer(minLength: 0)
                circleButton("trash", tint: .red, help: "Delete this page", label: "Delete page") {
                    model.confirmDelete(page.id)
                }
            }
            .disabled(model.saving || model.rotating)
            .padding(8)
        }
    }

    private func circleButton(_ symbol: String, tint: Color = .primary, help: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var pageStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.pages.count == 1 ? "1 page" : "\(model.pages.count) pages")
                    .font(.callout).foregroundStyle(.secondary)
                if model.pages.count > 1 {
                    Text("· Drag to reorder").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        thumbnail(page, number: index + 1)
                    }
                }
                .padding(2)
            }
            .frame(height: 96)
        }
    }

    private func thumbnail(_ page: ScannedPage, number: Int) -> some View {
        let selected = page.id == model.selectedID
        return Image(nsImage: page.thumbnail)
            .resizable().scaledToFit()
            .frame(width: 66, height: 90)
            .border(Color.secondary.opacity(0.35), width: 0.5)
            .overlay(alignment: .bottomTrailing) {
                Text("\(number)").font(.caption2.weight(.medium))
                    .padding(.horizontal, 4).background(.regularMaterial, in: Capsule()).padding(3)
            }
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.accentColor, lineWidth: selected ? 2 : 0).padding(-2))
            .onTapGesture { model.select(page.id) }
            .onDrag {
                draggingPage = page.id
                return NSItemProvider(object: page.id.uuidString as NSString)
            }
            .onDrop(of: [UTType.text], delegate: PageDropDelegate(target: page.id, model: model, dragging: $draggingPage))
            .contextMenu {
                Button("Turn Left") { model.rotate(page.id, clockwise: false) }.disabled(model.saving || model.rotating)
                Button("Turn Right") { model.rotate(page.id, clockwise: true) }.disabled(model.saving || model.rotating)
                Divider()
                Button("Move Left") { model.move(page.id, by: -1) }.disabled(number == 1)
                Button("Move Right") { model.move(page.id, by: 1) }.disabled(number == model.pages.count)
                Divider()
                Button("Delete Page…") { model.confirmDelete(page.id) }.disabled(model.saving || model.rotating)
            }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .top, spacing: 10) {
            statusView
            Spacer(minLength: 0)
            if model.busy {
                Button("Cancel") { model.cancel() }
                    .controlSize(.large)
            } else {
                Button { model.scanPage() } label: {
                    Label("Scan Page", systemImage: "scanner")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.saving)
            }
            Button {
                model.save()
            } label: {
                Text(saveLabel)
            }
            .controlSize(.large)
            .disabled(model.pages.isEmpty || model.busy || model.saving || model.rotating)
        }
    }

    private var saveLabel: String {
        let n = model.pages.count
        if n == 0 { return "Save…" }
        if model.format == .pdf {
            return model.savesOneFilePerPage && n > 1 ? "Save \(n) PDFs…" : "Save PDF (\(n) \(n == 1 ? "page" : "pages"))…"
        }
        return n == 1 ? "Save Image…" : "Save \(n) Images…"
    }

    @ViewBuilder private var statusView: some View {
        HStack(alignment: .top, spacing: 8) {
            switch model.state {
            case .scanning:
                ProgressView().controlSize(.small)
                Text("Scanning at \(model.resolution.rawValue) dpi. Printing waits until this is done.")
            case .waitingForPrinter:
                Image(systemName: "clock").foregroundStyle(.orange)
                Text("Waiting for the printer to finish. The scan starts by itself.")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(message).textSelection(.enabled)
            case .idle:
                if model.saving {
                    ProgressView().controlSize(.small)
                    Text("Saving…")
                } else if !model.lastSaved.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Saved \(model.lastSaved.count == 1 ? model.lastSaved[0].lastPathComponent : "\(model.lastSaved.count) files").")
                    Button("Show in Finder") { model.revealSaved() }.buttonStyle(.link)
                } else if model.pages.isEmpty {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    Text("Ready to scan").foregroundStyle(.secondary)
                } else {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    Text("Put the next page on the glass, or save what you have.").foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Lets a page be dragged along the strip: each page it passes over swaps places with it.
struct PageDropDelegate: DropDelegate {
    let target: UUID
    let model: ScanModel
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let id = dragging else { return }
        withAnimation(.easeInOut(duration: 0.15)) { model.reorder(id, onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
