import SwiftUI
import UniformTypeIdentifiers

// MARK: - Navigation

/// The three pages of the main window. The window opens on Home; Print and Scan are pages inside it,
/// not windows of their own, so the two jobs are never on screen side by side.
enum AppPage {
    case home, print, scan
}

@MainActor
final class Navigator: ObservableObject {
    static let shared = Navigator()
    @Published var page: AppPage = .home
}

extension PrinterStatus {
    /// Dot colour and text shown wherever the printer state is displayed.
    var badge: (color: Color, text: String) {
        switch self {
        case .checking: return (.gray, "Checking printer…")
        case .ready: return (.green, "Printer ready")
        case .printing: return (.orange, "Printer busy")
        case .offline: return (.red, "Printer not found — turn it on and check the USB cable")
        case .stopped: return (.red, "Print queue stopped — check paper and warning lights")
        case .missingQueue: return (.red, "No print queue for the G2010 — add the printer in System Settings")
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
            VStack(spacing: 24) {
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
            .frame(maxWidth: .infinity)

            Divider()
            statusPanel
                .frame(width: 210)
        }
        .frame(minWidth: 600, minHeight: 440)
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
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(badge.color).frame(width: 9, height: 9).padding(.top, 5)
                Text(badge.text).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxHeight: .infinity)
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
                Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(Color.accentColor)
                Text(title).font(.title2)
                Text(caption ?? " ").font(.caption).foregroundStyle(.orange)
            }
            .frame(width: 170, height: 170)
            .background(Color.secondary.opacity(hovering ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
