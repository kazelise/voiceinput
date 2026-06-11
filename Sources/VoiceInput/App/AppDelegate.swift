import AppKit
import Combine
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core singletons

    private let settings = AppSettings.shared
    private let appState = AppState.shared

    // MARK: - Subsystems

    private let keyMonitor = KeyMonitor()
    private let textInjector = TextInjector()
    private let mediaController = MediaController()

    private lazy var overlayPanel: OverlayPanel = {
        OverlayPanel(state: appState, settings: settings)
    }()

    private lazy var refiner: Refiner = {
        Refiner(settings: settings, vocabulary: VocabularyStore.shared)
    }()

    private lazy var dictationController: DictationController = {
        let dc = DictationController(
            settings: settings,
            appState: appState,
            refiner: refiner,
            textInjector: textInjector,
            mediaController: mediaController,
            overlayPanel: overlayPanel
        )
        // Wire external-stop and cancel callbacks to KeyMonitor state machine.
        dc.onSessionEndedExternally = { [weak self] in
            self?.keyMonitor.externalStop()
        }
        dc.onSessionCancelled = { [weak self] in
            self?.keyMonitor.reset()
        }
        return dc
    }()

    // MARK: - Status item

    private var statusItem: NSStatusItem?
    private var enableMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    // Debounce timer for hotkey rewire.
    private var rewireWorkItem: DispatchWorkItem?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force accessory policy (no Dock icon).
        NSApp.setActivationPolicy(.accessory)

        buildStatusItem()
        requestPermissionsOnLaunch()
        wireKeyMonitor()
        observeSettings()

        // Set initial hotkey label on the overlay.
        dictationController.updateHotkeyLabel(settings.hotkeyDisplayName)

        // Listen for preview-overlay notification from the Appearance settings tab.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreviewOverlayNotification(_:)),
            name: Notification.Name("VoiceInputPreviewOverlay"),
            object: nil
        )

        Log.app.info("VoiceInput launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running after settings window closes — hotkey must remain active.
        return false
    }

    // MARK: - Preview overlay notification

    @objc private func handlePreviewOverlayNotification(_ notification: Notification) {
        dictationController.showPreviewOverlay()
    }

    // MARK: - Status item construction

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VoiceInput")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        // Status line (disabled, just informational).
        let statusLine = NSMenuItem(title: "VoiceInput", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        menu.addItem(NSMenuItem.separator())

        // Enable / Disable toggle.
        let enableItem = NSMenuItem(
            title: settings.appEnabled ? "Disable VoiceInput" : "Enable VoiceInput",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enableItem.target = self
        menu.addItem(enableItem)
        enableMenuItem = enableItem

        menu.addItem(NSMenuItem.separator())

        // Settings…
        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit VoiceInput",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        item.menu = menu
    }

    @objc private func toggleEnabled() {
        settings.appEnabled.toggle()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    // MARK: - Permissions on launch

    private func requestPermissionsOnLaunch() {
        // Microphone: request access so macOS shows the permission dialog.
        PermissionStatus.shared.grantMicrophone()

        // Accessibility: prompt user if not already trusted.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        PermissionStatus.shared.refresh()
    }

    // MARK: - KeyMonitor wiring

    private func wireKeyMonitor() {
        keyMonitor.stop()

        guard settings.appEnabled else { return }

        let customShortcut = (settings.hotkeyKey == .customShortcut)
            ? settings.hotkeyShortcut
            : nil

        keyMonitor.configure(
            key: settings.hotkeyKey,
            customShortcut: customShortcut,
            tapHoldThresholdMs: settings.tapHoldThresholdMs,
            doublePressWindowMs: settings.doublePressWindowMs,
            holdForgiveMs: settings.holdForgiveMs
        )

        keyMonitor.onStart = { [weak self] kind in
            self?.dictationController.beginSession(kind: kind)
        }
        keyMonitor.onStop = { [weak self] in
            self?.dictationController.endSession()
        }

        keyMonitor.start()
    }

    // MARK: - Settings observation

    private func observeSettings() {
        // Enable/disable toggle — rewire or tear down KeyMonitor.
        settings.$appEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.enableMenuItem?.title = enabled ? "Disable VoiceInput" : "Enable VoiceInput"
                if enabled {
                    self.wireKeyMonitor()
                } else {
                    self.keyMonitor.stop()
                    self.dictationController.cancelSession()
                }
            }
            .store(in: &cancellables)

        // Hotkey-related settings — debounce rewire at 300 ms.
        let hotkeyPublisher = settings.$hotkeyKey
            .combineLatest(
                settings.$customHotkeyKeyCode,
                settings.$customHotkeyModifierFlags,
                settings.$customHotkeyKeyEquivalent
            )
            .map { _ in () }

        let timingPublisher = settings.$tapHoldThresholdMs
            .combineLatest(
                settings.$doublePressWindowMs,
                settings.$holdForgiveMs
            )
            .map { _ in () }

        hotkeyPublisher
            .merge(with: timingPublisher)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.scheduleHotkeyRewire()
            }
            .store(in: &cancellables)
    }

    private func scheduleHotkeyRewire() {
        rewireWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.wireKeyMonitor()
            self.dictationController.updateHotkeyLabel(self.settings.hotkeyDisplayName)
        }
        rewireWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
