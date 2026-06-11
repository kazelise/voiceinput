import AppKit
import Combine

/// Drives `NSApp.appearance` from `AppSettings.shared.appearancePreference`
/// ("system" / "light" / "dark").
///
/// Call `AppearanceManager.shared.start()` once, as early as possible in the
/// application lifecycle — it is safe to call before any windows exist because
/// setting `NSApp.appearance` affects future window creation as well as
/// already-visible ones.  A Combine subscription keeps the setting in sync for
/// the lifetime of the application.
final class AppearanceManager {
    static let shared = AppearanceManager()

    private var cancellable: AnyCancellable?

    private init() {}

    /// Applies the current preference immediately and begins observing changes.
    func start() {
        // Apply synchronously so the very first window inherits the right look.
        apply(AppSettings.shared.appearancePreference)

        // Re-apply whenever the setting changes.  The sink is always delivered
        // on the main thread because `AppSettings` publishes on the main actor
        // (all its didSet calls run there, and Combine propagates on the same
        // scheduler for @Published unless explicitly switched).
        cancellable = AppSettings.shared.$appearancePreference
            .dropFirst()                    // already applied above
            .receive(on: DispatchQueue.main)
            .sink { [weak self] preference in
                self?.apply(preference)
            }
    }

    // MARK: - Private

    private func apply(_ preference: String) {
        switch preference {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default: // "system" or any unrecognised value
            NSApp.appearance = nil
        }
    }
}
