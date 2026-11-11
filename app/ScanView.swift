import SwiftUI

/// The Scan window: settings on the left, the page on the glass in the middle, the pages scanned so far below.
struct ScanView: View {
    @ObservedObject var model: ScanModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                settings
                    .frame(width: 200)
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
                Text(model.format == .pdf ? "One PDF with all the pages."
                     : "One \(model.format.rawValue) file for each page.")
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

    @ViewBuilder private var pageStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.pages.count == 1 ? "1 page" : "\(model.pages.count) pages")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if let page = model.selectedPage {
                    Button("Delete Page") { model.delete(page.id) }
                        .buttonStyle(.link)
                }
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
            .contextMenu {
                Button("Move Left") { model.move(page.id, by: -1) }.disabled(number == 1)
                Button("Move Right") { model.move(page.id, by: 1) }.disabled(number == model.pages.count)
                Divider()
                Button("Delete Page") { model.delete(page.id) }
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
            }
            Button {
                model.save()
            } label: {
                Text(saveLabel)
            }
            .controlSize(.large)
            .disabled(model.pages.isEmpty || model.state == .scanning)
        }
    }

    private var saveLabel: String {
        let n = model.pages.count
        if n == 0 { return "Save…" }
        if model.format == .pdf { return "Save PDF (\(n) \(n == 1 ? "page" : "pages"))…" }
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
                if !model.lastSaved.isEmpty {
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
