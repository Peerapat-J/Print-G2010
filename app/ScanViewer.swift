import SwiftUI

/// A large, zoomable view of the selected scanned page, in its own window so it can be resized or
/// kept open while pages are scanned. It follows the selection in the Scan window.
struct ScanViewer: View {
    @ObservedObject var model: ScanModel
    @Environment(\.displayScale) private var displayScale
    /// The scan at its full resolution (the Scan window only keeps a reduced copy).
    @State private var full: NSImage?
    /// Screen pixels per image pixel: 1 is "100%", every dot of the scan on one dot of the screen.
    /// nil fits the whole page in the window.
    @State private var scale: CGFloat?
    @State private var viewport: CGSize = .zero

    private var index: Int? { model.pages.firstIndex { $0.id == model.selectedID } }

    private var title: String {
        guard let i = index else { return "Scan Preview" }
        return "Page \(i + 1) of \(model.pages.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            GeometryReader { geo in
                content(in: geo.size)
                    .onAppear { viewport = geo.size }
                    .onChange(of: geo.size) { _, new in viewport = new }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .navigationTitle(title)
        .task(id: model.selectedID) {
            scale = nil
            full = nil
            guard let url = model.selectedPage?.url else { return }
            full = await Task.detached { ScanImage.fullSize(url) }.value
        }
    }

    // MARK: Zoom

    private var fitScale: CGFloat {
        guard let full, viewport.width > 0, viewport.height > 0 else { return 1 }
        return min(viewport.width * displayScale / full.size.width,
                   viewport.height * displayScale / full.size.height)
    }

    private var currentScale: CGFloat { scale ?? fitScale }

    private func zoom(by factor: CGFloat) {
        scale = min(max(currentScale * factor, 0.05), 4)
    }

    // MARK: Views

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled((index ?? 0) == 0)
                .help("Previous page")
            Text(title).font(.callout).monospacedDigit()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(index == nil || index! >= model.pages.count - 1)
                .help("Next page")
            Spacer()
            Button("Fit") { scale = nil }
                .keyboardShortcut("0")
                .disabled(scale == nil)
                .help("Show the whole page (⌘0)")
            Button { zoom(by: 1 / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-")
                .help("Zoom out (⌘−)")
            Text("\(Int((currentScale * 100).rounded()))%")
                .font(.callout).monospacedDigit()
                .frame(width: 48)
            Button { zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("=")
                .help("Zoom in (⌘+)")
            Button("100%") { scale = 1 }
                .disabled(scale == 1)
                .help("Actual size: one dot of the scan for each dot of the screen")
        }
    }

    @ViewBuilder private func content(in size: CGSize) -> some View {
        if let full {
            let s = scale ?? fitScale
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: full)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: full.size.width * s / displayScale, height: full.size.height * s / displayScale)
                    .border(Color.secondary.opacity(0.35), width: 0.5)
                    .padding(12)
                    .frame(minWidth: size.width, minHeight: size.height)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .simultaneousGesture(MagnifyGesture().onEnded { zoom(by: $0.magnification) })
        } else if index == nil {
            VStack(spacing: 6) {
                Image(systemName: "doc").font(.largeTitle).foregroundStyle(.secondary)
                Text("No page scanned yet").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func step(_ offset: Int) {
        guard let i = index, model.pages.indices.contains(i + offset) else { return }
        model.select(model.pages[i + offset].id)
    }
}
