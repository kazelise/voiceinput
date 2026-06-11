import AppKit
import SwiftUI

/// Owns the single History window. Mirrors the Settings window idiom: hidden
/// title (a "History" header is drawn in-content), transparent titlebar,
/// full-size content, `Theme.chrome` background. Created lazily and reused.
final class HistoryWindowController {
    static let shared = HistoryWindowController()

    private var window: NSWindow?

    private init() {}

    /// Creates (or reuses) the History window and brings it forward, activating
    /// the app — works even with an `.accessory` activation policy.
    func show() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "History"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        window.setFrameAutosaveName("VoiceInputHistoryWindow")
        window.backgroundColor = .clear

        let root = HistoryView()
            .environmentObject(HistoryStore.shared)
            .environmentObject(AppSettings.shared)

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hosting

        if window.frame.size.width < 760 || window.frame.size.height < 520 {
            window.setContentSize(NSSize(width: 880, height: 600))
        }
        window.center()

        return window
    }
}
