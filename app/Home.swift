import SwiftUI
import UniformTypeIdentifiers

// MARK: - Navigation

/// The three pages of the main window. The window opens on Home; Print and Scan are pages inside it,
/// not windows of their own, so the two jobs are never on screen side by side.
enum AppPage: String {
    case home, print, scan

    /// The size the window takes (the area below the title bar, in points) when this page opens: Home is a small
    /// launcher, Print and Scan need room for their lists and previews. The user can still resize.
    var contentSize: CGSize {
        switch self {
        case .home: return CGSize(width: 620, height: 312)
        case .print: return CGSize(width: 560, height: 600)
        case .scan: return CGSize(width: 720, height: 580)
        }
    }
}

@MainActor
final class Navigator: ObservableObject {
    static let shared = Navigator()
    /// G2010_PAGE=print or scan opens the app on that page (for checking a page without clicking).
    @Published var page: AppPage = AppPage(rawValue: ProcessInfo.processInfo.environment["G2010_PAGE"] ?? "") ?? .home
}

extension PrinterStatus {
    /// Dot colour and text shown wherever the printer state is displayed: a short title, and for a
    /// problem a hint on what to do about it (shown on its own line where there is room).
    var badge: (color: Color, title: String, hint: String?) {
        switch self {
        case .checking: return (.gray, "Checking printer…", nil)
        case .ready: return (.green, "Printer ready", nil)
        case .printing: return (.orange, "Printer busy", nil)
        case .offline: return (.red, "Printer not found", "Turn it on and check the USB cable")
        case .stopped: return (.red, "Print queue stopped", "Check paper and warning lights")
        case .missingQueue: return (.red, "No print queue", "Add the G2010 in System Settings")
        }
    }
}

// MARK: - Root

struct RootView: View {
    @ObservedObject private var nav = Navigator.shared

    var body: some View {
        Group {
            switch nav.page {
            case .home:
                HomeView(printModel: PrintModel.shared, scan: ScanModel.shared)
            case .print:
                VStack(spacing: 0) {
                    PageBar(title: "Print")
                    Divider()
                    ContentView(model: PrintModel.shared)
                }
            case .scan:
                VStack(spacing: 0) {
                    PageBar(title: "Scan")
                    Divider()
                    ScanView(model: ScanModel.shared)
                }
            }
        }
        // The printer state is shown on Home and on the Print page, so poll it for the whole window.
        .task { await PrintModel.shared.monitorPrinter() }
        // The window changes size to suit the page that is showing.
        .background(WindowSizer(page: nav.page))
    }
}

/// Resizes the window that holds it whenever the page changes, keeping its top-left corner in place.
struct WindowSizer: NSViewRepresentable {
    let page: AppPage

    final class Coordinator { var last: AppPage? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.last != page else { return }
        let first = context.coordinator.last == nil
        context.coordinator.last = page
        let size = page.contentSize
        // Wait a moment so the window has taken the new page's minimum size first; otherwise the
        // old page's minimum would stop it from shrinking.
        DispatchQueue.main.asyncAfter(deadline: .now() + (first ? 0.05 : 0.03)) {
            view.window?.setContentSizeKeepingTopLeft(size, animate: !first)
        }
    }
}

extension NSWindow {
    /// Sizes the window so the area below the title bar is `size`. The title bar and any other
    /// space the window adds around its content (`contentLayoutRect`) come on top of that.
    func setContentSizeKeepingTopLeft(_ size: CGSize, animate: Bool) {
        let chrome = CGSize(width: frame.width - contentLayoutRect.width,
                            height: frame.height - contentLayoutRect.height)
        var next = frame
        next.size = CGSize(width: size.width + chrome.width, height: size.height + chrome.height)
        next.origin.y = frame.maxY - next.height
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            next.size.width = min(next.width, visible.width)
            next.size.height = min(next.height, visible.height)
            next.origin.x = min(max(next.minX, visible.minX), visible.maxX - next.width)
            next.origin.y = min(max(next.minY, visible.minY), visible.maxY - next.height)
        }
        setFrame(next, display: true, animate: animate)
    }
}

/// The strip above the Print and Scan pages with the way back to Home.
struct PageBar: View {
    let title: String
    @ObservedObject private var nav = Navigator.shared

    var body: some View {
        HStack(spacing: 10) {
            Button { nav.page = .home } label: {
                Label("Home", systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to Home (⌘[)")
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var printModel: PrintModel
    @ObservedObject var scan: ScanModel
    @ObservedObject private var nav = Navigator.shared
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                HStack(spacing: 24) {
                    HomeTile(title: "Print", symbol: "printer.fill",
                             caption: printModel.busy ? "Printing…" : nil) { nav.page = .print }
                    HomeTile(title: "Scan", symbol: "scanner",
                             caption: scan.busy ? (scan.scanning ? "Scanning…" : "Waiting for the printer…") : nil) {
                        nav.page = .scan
                    }
                }
                dropZone
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 392, maxWidth: .infinity)

            Divider()
            statusPanel
                .frame(width: 220)
        }
        .frame(minWidth: 612, minHeight: 312)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        printModel.add([url])
                        nav.page = .print
                    }
                }
            }
            return true
        }
    }

    /// Files dropped anywhere on the window go straight to the Print page; this just says so.
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus").font(.title).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drop PDF files or images here")
                    Text("They go straight to the print list").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 84)
    }

    private var statusPanel: some View {
        let badge = printModel.printer.badge
        return VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "printer.fill").font(.system(size: 54)).foregroundStyle(.secondary)
            Text("Canon G2010").font(.title3.weight(.semibold))
            HStack(spacing: 6) {
                Circle().fill(badge.color).frame(width: 9, height: 9)
                Text(badge.title).font(.callout).foregroundStyle(.secondary)
            }
            if let hint = badge.hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxHeight: .infinity)
        // At the bottom edge, so the printer and its state stay centred.
        .overlay(alignment: .bottom) { versionBadge }
    }

    /// The app's version, from its Info.plist, in a small capsule.
    @ViewBuilder private var versionBadge: some View {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            Text("v\(version)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                .padding(.bottom, 14)
                .help("Print G2010 version \(version)")
        }
    }
}

struct HomeTile: View {
    let title: String
    let symbol: String
    var caption: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 64)
                Text(title).font(.title2)
            }
            .frame(width: 160, height: 160)
            // The status ("Printing…") sits on the bottom edge so the icon and name stay centred.
            .overlay(alignment: .bottom) {
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.orange).padding(.bottom, 10)
                }
            }
            .background(Color.secondary.opacity(hovering ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}
