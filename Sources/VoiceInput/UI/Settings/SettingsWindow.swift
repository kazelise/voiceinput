import AppKit
import SwiftUI

/// Owns the single Settings window. Mirrors macOS System Settings: hidden title
/// (drawn in-content), transparent titlebar, full-size content, `Theme.chrome`
/// background. Creates the window lazily and reuses it.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var activationObserver: NSObjectProtocol?

    private init() {}

    /// Creates (or reuses) the Settings window and brings it forward, activating
    /// the app — works even with an `.accessory` activation policy.
    func show() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }

        PermissionStatus.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 560)
        window.setFrameAutosaveName("VoiceInputSettingsWindow")
        window.backgroundColor = .clear

        // One Refiner drives both Test buttons; built once per window.
        let refiner = Refiner(settings: .shared, vocabulary: .shared)

        let root = SettingsRootView(refiner: refiner)
            .environmentObject(AppSettings.shared)
            .environmentObject(VocabularyStore.shared)
            .environmentObject(PermissionStatus.shared)

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hosting

        // Keep permission state honest when the user returns from System Settings.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            PermissionStatus.shared.refresh()
        }

        return window
    }
}
