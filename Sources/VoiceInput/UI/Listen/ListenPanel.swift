import AppKit
import Combine
import SwiftUI

/// The Live Captions window: a borderless, non-activating glass panel hosting
/// `ListenView`. Floats over everything (calls, videos), never steals focus,
/// drags via grabber/background, and resizes from any edge. Two layouts —
/// two-column ("dual") and a wide caption strip ("bar") — each with its own
/// remembered size and origin; toggling animates between them.
final class ListenPanel {
    private let state: ListenState
    private let settings: AppSettings
    private weak var controller: ListenController?

    private var panel: NSPanel?
    private let resizeController = ListenResizeController()
    private var moveObserver: Any?
    private var isProgrammaticMove = false
    private var modeAnimationToken = 0
    private var cancellables = Set<AnyCancellable>()

    init(state: ListenState, settings: AppSettings, controller: ListenController) {
        self.state = state
        self.settings = settings
        self.controller = controller

        // Layout toggle re-frames the panel to the other mode's size/origin.
        settings.$listenMode
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.adoptModeLayout() }
            .store(in: &cancellables)
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
        resizeController.cancel()
        NSCursor.arrow.set()
        panel?.orderOut(nil)
    }

    // MARK: - Sizing (card size + 80 pt shadow canvas)

    private var contentSize: NSSize {
        if settings.listenMode == "bar" {
            return NSSize(width: settings.listenBarWidth + 80, height: settings.listenBarHeight + 80)
        }
        return NSSize(width: settings.listenWidth + 80, height: settings.listenHeight + 80)
    }

    // MARK: - Construction

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let root = ListenView(
            state: state,
            settings: settings,
            resizeController: resizeController,
            onClose: { [weak self] in self?.controller?.stop() },
            onClear: { [weak self] in self?.controller?.clearTranscripts() }
        )
        let hosting = ListenHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]

        let size = contentSize
        let panel = ListenNonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        resizeController.panel = panel
        resizeController.settings = settings

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, let frame = self.panel?.frame,
                  !self.isProgrammaticMove, !self.resizeController.isResizing else { return }
            self.persistOrigin(frame.origin)
        }

        self.panel = panel
        return panel
    }

    // MARK: - Positioning

    private func position(_ panel: NSPanel) {
        isProgrammaticMove = true
        defer { isProgrammaticMove = false }

        let size = contentSize
        if originSaved {
            let saved = NSRect(x: savedOriginX, y: savedOriginY, width: size.width, height: size.height)
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
        let x = area.midX - size.width / 2
        // Bar mode sits low like real captions; dual sits high to clear controls.
        let y = settings.listenMode == "bar"
            ? area.minY + 90
            : area.maxY - size.height - 60
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    /// Re-frame to the toggled mode: the new mode's saved spot, else keep the
    /// current center. Animated so the glass morphs rather than jumps.
    private func adoptModeLayout() {
        guard let panel, panel.isVisible else { return }
        resizeController.cancel()
        let size = contentSize
        isProgrammaticMove = true

        let frame: NSRect
        if originSaved,
           NSScreen.screens.contains(where: {
               $0.visibleFrame.intersection(NSRect(x: savedOriginX, y: savedOriginY,
                                                   width: size.width, height: size.height)).width >= 100
           }) {
            frame = NSRect(x: savedOriginX, y: savedOriginY, width: size.width, height: size.height)
        } else {
            let old = panel.frame
            frame = NSRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2,
                           width: size.width, height: size.height)
        }

        modeAnimationToken &+= 1
        let token = modeAnimationToken
        let duration = panel.animationResizeTime(frame)
        panel.setFrame(frame, display: true, animate: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            guard let self, let panel = self.panel, self.modeAnimationToken == token else { return }
            self.isProgrammaticMove = false
            self.persistOrigin(panel.frame.origin)
        }
    }

    // MARK: - Per-mode origin persistence

    private var originSaved: Bool {
        settings.listenMode == "bar" ? settings.listenBarOriginSaved : settings.listenOriginSaved
    }
    private var savedOriginX: Double {
        settings.listenMode == "bar" ? settings.listenBarOriginX : settings.listenOriginX
    }
    private var savedOriginY: Double {
        settings.listenMode == "bar" ? settings.listenBarOriginY : settings.listenOriginY
    }
    private func persistOrigin(_ origin: NSPoint) {
        if settings.listenMode == "bar" {
            settings.listenBarOriginX = origin.x
            settings.listenBarOriginY = origin.y
            settings.listenBarOriginSaved = true
        } else {
            settings.listenOriginX = origin.x
            settings.listenOriginY = origin.y
            settings.listenOriginSaved = true
        }
    }
}

// MARK: - Resize controller (mirrors BoxResizeController, keyed by listen mode)

final class ListenResizeController {
    weak var panel: NSPanel?
    weak var settings: AppSettings?

    private(set) var isResizing = false
    private var startFrame: NSRect = .zero
    private var startMouse: NSPoint = .zero

    private var isBar: Bool { settings?.listenMode == "bar" }
    private var minSize: NSSize {
        isBar ? NSSize(width: 480 + 80, height: 120 + 80) : NSSize(width: 520 + 80, height: 220 + 80)
    }
    private var maxSize: NSSize {
        isBar ? NSSize(width: 1800 + 80, height: 320 + 80) : NSSize(width: 1500 + 80, height: 820 + 80)
    }

    func begin() {
        guard let panel else { return }
        startFrame = panel.frame
        startMouse = NSEvent.mouseLocation
        isResizing = true
    }

    func update(edges: ResizeEdges) {
        guard isResizing, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y

        var f = startFrame
        if edges.contains(.right)  { f.size.width  = startFrame.width + dx }
        if edges.contains(.left)   { f.size.width  = startFrame.width - dx
                                     f.origin.x    = startFrame.origin.x + dx }
        if edges.contains(.top)    { f.size.height = startFrame.height + dy }
        if edges.contains(.bottom) { f.size.height = startFrame.height - dy
                                     f.origin.y    = startFrame.origin.y + dy }

        let w = min(max(f.size.width, minSize.width), maxSize.width)
        let h = min(max(f.size.height, minSize.height), maxSize.height)
        if edges.contains(.left)   { f.origin.x += f.size.width - w }
        if edges.contains(.bottom) { f.origin.y += f.size.height - h }
        f.size.width = w
        f.size.height = h
        panel.setFrame(f, display: true)
    }

    func end() {
        guard isResizing else { return }
        isResizing = false
        guard let panel, let settings else { return }
        if settings.listenMode == "bar" {
            settings.listenBarWidth = panel.frame.width - 80
            settings.listenBarHeight = panel.frame.height - 80
            settings.listenBarOriginX = panel.frame.origin.x
            settings.listenBarOriginY = panel.frame.origin.y
            settings.listenBarOriginSaved = true
        } else {
            settings.listenWidth = panel.frame.width - 80
            settings.listenHeight = panel.frame.height - 80
            settings.listenOriginX = panel.frame.origin.x
            settings.listenOriginY = panel.frame.origin.y
            settings.listenOriginSaved = true
        }
    }

    func cancel() {
        guard isResizing else { return }
        isResizing = false
        NSCursor.arrow.set()
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
