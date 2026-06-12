import AppKit
import SwiftUI

/// The Live Captions window: a borderless, non-activating glass panel hosting
/// the two-column `ListenView`. Floats over everything (including the call or
/// video it is captioning), drags via grabber/background, never steals focus.
final class ListenPanel {
    private let state: ListenState
    private let settings: AppSettings
    private weak var controller: ListenController?

    private var panel: NSPanel?
    private var moveObserver: Any?
    private var isProgrammaticMove = false

    private let contentSize = NSSize(width: 840, height: 420)

    init(state: ListenState, settings: AppSettings, controller: ListenController) {
        self.state = state
        self.settings = settings
        self.controller = controller
    }

    deinit {
        if let o = moveObserver { NotificationCenter.default.removeObserver(o) }
    }

    func show() {
        let panel = ensurePanel()
        position(panel)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    // MARK: - Construction

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let root = ListenView(
            state: state,
            settings: settings,
            onClose: { [weak self] in self?.controller?.stop() },
            onClear: { [weak self] in self?.controller?.clearTranscripts() }
        )
        let hosting = ListenHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]

        let panel = ListenNonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        panel.contentView = hosting

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, let frame = self.panel?.frame, !self.isProgrammaticMove else { return }
            self.settings.listenOriginX = frame.origin.x
            self.settings.listenOriginY = frame.origin.y
            self.settings.listenOriginSaved = true
        }

        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        isProgrammaticMove = true
        defer { isProgrammaticMove = false }

        if settings.listenOriginSaved {
            let saved = NSRect(x: settings.listenOriginX, y: settings.listenOriginY,
                               width: contentSize.width, height: contentSize.height)
            let visible = NSScreen.screens.contains {
                let overlap = $0.visibleFrame.intersection(saved)
                return overlap.width >= 100 && overlap.height >= 50
            }
            if visible {
                panel.setFrame(saved, display: true)
                return
            }
        }

        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let area = screen.visibleFrame
        // Captions live near the top so they don't cover meeting controls.
        let x = area.midX - contentSize.width / 2
        let y = area.maxY - contentSize.height - 60
        panel.setFrame(NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height),
                       display: true)
    }
}

private final class ListenNonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// First-click responsiveness in a never-key panel (same fix as the voice box).
private final class ListenHostingView: NSHostingView<ListenView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
