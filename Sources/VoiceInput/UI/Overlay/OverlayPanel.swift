import AppKit
import SwiftUI

/// The floating dictation HUD window.
///
/// Owns a borderless, non-activating `NSPanel` that hosts the SwiftUI
/// `GlassVoiceBox`. The panel never becomes key or main, joins all Spaces, and
/// floats above ordinary windows. Positioning, show/dismiss animation, and the
/// Esc-to-cancel monitors live here; everything visible is driven reactively by
/// `AppState`/`AppSettings` from inside the SwiftUI box.
///
/// The panel only *renders* the error phase (red flash + error text). The 2-second
/// error dwell, the `dismiss()` call, and the return to `.idle` are owned by
/// `DictationController` so media-resume and KeyMonitor reset stay sequenced.
final class OverlayPanel {
    /// Fired when the user taps the glass "Stop" capsule.
    var onStop: (() -> Void)?
    /// Fired on the glass "Cancel" capsule or on Esc.
    var onCancel: (() -> Void)?

    private let state: AppState
    private let settings: AppSettings
    private let hotkeyLabel = HotkeyLabelModel()

    /// Drives the SwiftUI show/dismiss scale+fade transition.
    private let presentation = PresentationModel()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayRootView>?

    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?

    /// Guards against a dismiss animation completion ordering out a panel that
    /// was re-shown in the meantime.
    private var showToken = 0

    init(state: AppState, settings: AppSettings) {
        self.state = state
        self.settings = settings
    }

    deinit {
        // Monitors must be torn down off the panel's lifetime. deinit runs on
        // whatever thread releases us; the removals are cheap and thread-safe
        // for NSEvent monitors created on the main thread, but guard anyway.
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m) }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Public API

    /// Shows the box on the screen containing the mouse pointer, non-activating.
    func show() {
        let panel = ensurePanel()
        positionPanel(panel)

        showToken += 1
        // Start hidden, then animate in via SwiftUI once on screen.
        presentation.isPresented = false
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        // Next runloop tick so the hosting view has laid out at the start state
        // before we flip the flag and let the spring run.
        DispatchQueue.main.async { [weak self] in
            self?.presentation.isPresented = true
        }

        startEscMonitors()
    }

    /// Animates the box out and orders the panel off screen.
    func dismiss() {
        guard let panel else { return }
        stopEscMonitors()

        let token = showToken
        presentation.isPresented = false

        // Order out after the SwiftUI dismiss transition (0.25 s) finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self, self.showToken == token else { return }
            panel.orderOut(nil)
        }
    }

    /// Updates the "Stop" badge with the user's current hotkey display name.
    func updateHotkeyLabel(_ display: String) {
        hotkeyLabel.label = display
    }

    // MARK: - Panel construction

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let root = OverlayRootView(
            state: state,
            settings: settings,
            hotkeyLabel: hotkeyLabel,
            presentation: presentation,
            onStop: { [weak self] in self?.onStop?() },
            onCancel: { [weak self] in self?.onCancel?() }
        )

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]

        let panel = NonActivatingPanel(
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
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        hosting.frame = NSRect(origin: .zero, size: contentSize)
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting
        return panel
    }

    /// The hosting size. The box is 680 wide; the SwiftUI root adds 40 pt of
    /// padding on each side for the shadow, and the vertical content varies with
    /// the transcript (1–3 lines), so we give a generous fixed canvas the box
    /// centers in — tall enough for the 3-line case plus the soft shadow.
    private var contentSize: NSSize {
        NSSize(width: 680 + 80, height: 320)
    }

    // MARK: - Positioning

    private func positionPanel(_ panel: NSPanel) {
        let screen = screenContainingMouse()
        let area = screen.visibleFrame
        let size = contentSize

        let x = area.midX - size.width / 2
        // voiceBoxVerticalPosition is a fraction from the bottom; center the box
        // vertically on that line. AppKit screen coords originate bottom-left.
        let fraction = max(0.0, min(1.0, settings.voiceBoxVerticalPosition))
        let centerY = area.minY + area.height * CGFloat(fraction)
        let y = centerY - size.height / 2

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height),
                       display: true)
    }

    private func screenContainingMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    // MARK: - Esc monitors

    private func startEscMonitors() {
        stopEscMonitors()
        // Global: Esc pressed in any other app while the box is up.
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.onCancel?()
            }
        }
        // Local: Esc pressed while one of our own (non-key) elements has focus.
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.onCancel?()
                return nil
            }
            return event
        }
    }

    private func stopEscMonitors() {
        if let m = escGlobalMonitor {
            NSEvent.removeMonitor(m)
            escGlobalMonitor = nil
        }
        if let m = escLocalMonitor {
            NSEvent.removeMonitor(m)
            escLocalMonitor = nil
        }
    }
}

// MARK: - Non-activating panel subclass

/// An `NSPanel` that refuses key/main status so showing the HUD never steals
/// focus from the app the user is dictating into.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Presentation model

/// Drives the SwiftUI show/dismiss transition (scale 0.97→1 + fade).
fileprivate final class PresentationModel: ObservableObject {
    @Published var isPresented = false
}

// MARK: - SwiftUI root

/// Wraps `GlassVoiceBox` and applies the panel's appear/disappear animation.
/// Not part of the public contract — internal to the overlay.
fileprivate struct OverlayRootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject var hotkeyLabel: HotkeyLabelModel
    @ObservedObject var presentation: PresentationModel

    var onStop: () -> Void
    var onCancel: () -> Void

    var body: some View {
        GlassVoiceBox(
            state: state,
            settings: settings,
            hotkeyLabel: hotkeyLabel,
            onStop: onStop,
            onCancel: onCancel
        )
        .scaleEffect(presentation.isPresented ? 1 : 0.97)
        .opacity(presentation.isPresented ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: presentation.isPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
