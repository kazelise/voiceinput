import AVFoundation
import AppKit
import ApplicationServices
import Combine
import Foundation

/// Tracks the OS-level permissions this app needs to work and exposes actions
/// to the settings UI. Values are refreshed on demand — nothing is observed
/// continuously, since macOS doesn't publish "permission changed" events.
final class PermissionStatus: ObservableObject {
    static let shared = PermissionStatus()

    enum State: Equatable {
        case granted
        case notDetermined  // user hasn't been asked yet → we can prompt
        case denied         // user denied (or restricted / parental controls)
    }

    @Published var microphone:   State = .notDetermined
    @Published var accessibility: State = .notDetermined

    private init() { refresh() }

    // MARK: - Refresh

    /// Refresh current state from the OS. Call on window show and on app
    /// activation (permissions may have changed in System Settings while the
    /// app was in the background).
    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphone = .granted
        case .notDetermined:
            microphone = .notDetermined
        case .denied, .restricted:
            microphone = .denied
        @unknown default:
            microphone = .denied
        }

        accessibility = AXIsProcessTrusted() ? .granted : .denied
    }

    // MARK: - Microphone

    func grantMicrophone() {
        switch microphone {
        case .granted:
            return
        case .notDetermined:
            // Native "Allow / Don't Allow" prompt, only works the first time.
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        case .denied:
            openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
    }

    // MARK: - Accessibility

    func grantAccessibility() {
        if accessibility == .granted { return }
        // AXIsProcessTrustedWithOptions(prompt:true) surfaces macOS's own
        // "Open System Settings" sheet the first time. On subsequent calls it is
        // a no-op — fall through to opening the pane directly.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // MARK: - Helpers

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    /// True only when every permission this app depends on is granted.
    var allGranted: Bool { microphone == .granted && accessibility == .granted }
}
