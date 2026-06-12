import AppKit
import Combine
import os.log

// MARK: - ListenState

/// Reactive state for the Live Captions window.
final class ListenState: ObservableObject {
    @Published var active = false
    @Published var connecting = false
    @Published var original = TranscriptSnapshot()
    @Published var translation = TranscriptSnapshot()
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?
}

// MARK: - ListenController

/// Live Captions: continuous transcription (+ inline Soniox one-way
/// translation) of either the system's own audio output or the microphone,
/// rendered in a two-column glass panel. Toggled by Fn+Space or the menu bar.
///
/// Target-language changes restart the WebSocket (Soniox config is fixed per
/// session) while CARRYING the text already shown; source changes swap the
/// audio capture without touching the session.
final class ListenController {
    let state = ListenState()

    private let settings: AppSettings
    private var panel: ListenPanel?

    private var session: ListenSession?
    private var micCapture: AudioCapture?
    private var systemCapture: SystemAudioCapture?

    /// Text carried across target-language restarts.
    private var carriedOriginal = ""
    private var carriedTranslation = ""

    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings

        settings.$listenTargetLanguage
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.restartSessionCarryingText() }
            .store(in: &cancellables)

        settings.$listenSource
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.restartCapture() }
            .store(in: &cancellables)
    }

    // MARK: - Public

    func toggle() {
        state.active ? stop() : start()
    }

    func start() {
        guard !state.active else { return }
        Log.app.info("Live Captions start (source=\(self.settings.listenSource))")
        state.active = true
        state.connecting = true
        state.errorMessage = nil
        state.original = TranscriptSnapshot()
        state.translation = TranscriptSnapshot()
        carriedOriginal = ""
        carriedTranslation = ""

        if panel == nil { panel = ListenPanel(state: state, settings: settings, controller: self) }
        panel?.show()

        startSession()
        startCapture()
    }

    func stop() {
        guard state.active else { return }
        Log.app.info("Live Captions stop")
        state.active = false
        stopCapture()
        session?.stop()
        session = nil
        panel?.dismiss()
    }

    func clearTranscripts() {
        carriedOriginal = ""
        carriedTranslation = ""
        state.original = TranscriptSnapshot()
        state.translation = TranscriptSnapshot()
        restartSessionCarryingText(carry: false)
    }

    // MARK: - Session

    private func startSession() {
        let newSession = ListenSession()
        session = newSession

        newSession.onConnected = { [weak self] in
            self?.state.connecting = false
        }
        newSession.onOriginal = { [weak self] snapshot in
            guard let self, self.state.active else { return }
            self.state.original = TranscriptSnapshot(
                finalText: self.carriedOriginal + snapshot.finalText,
                interimText: snapshot.interimText
            )
        }
        newSession.onTranslation = { [weak self] snapshot in
            guard let self, self.state.active else { return }
            self.state.translation = TranscriptSnapshot(
                finalText: self.carriedTranslation + snapshot.finalText,
                interimText: snapshot.interimText
            )
        }
        newSession.onError = { [weak self] message in
            guard let self, self.state.active else { return }
            self.state.errorMessage = message
            self.state.connecting = false
        }

        newSession.start(
            apiKey: settings.sonioxAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: settings.sonioxModel.trimmingCharacters(in: .whitespacesAndNewlines),
            languageHints: settings.languageHintsArray,
            targetLanguage: settings.listenTargetLanguage,
            vocabularyTerms: VocabularyStore.shared.sonioxTerms
        )
    }

    private func restartSessionCarryingText(carry: Bool = true) {
        guard state.active else { return }
        if carry {
            carriedOriginal = state.original.combined
            carriedTranslation = state.translation.combined
        }
        state.connecting = true
        state.errorMessage = nil
        session?.stop()
        startSession()
    }

    // MARK: - Capture

    private func startCapture() {
        if settings.listenSource == "mic" {
            let capture = AudioCapture()
            micCapture = capture
            capture.onChunk = { [weak self] chunk in self?.session?.sendAudio(chunk) }
            capture.onLevel = { [weak self] level in self?.state.audioLevel = level }
            do {
                try capture.start()
            } catch {
                state.errorMessage = "Microphone capture failed: \(error.localizedDescription)"
            }
        } else {
            let capture = SystemAudioCapture()
            systemCapture = capture
            capture.onChunk = { [weak self] chunk in self?.session?.sendAudio(chunk) }
            capture.onLevel = { [weak self] level in self?.state.audioLevel = level }
            capture.onError = { [weak self] message in
                guard let self, self.state.active else { return }
                self.state.errorMessage = message
            }
            capture.start()
        }
    }

    private func stopCapture() {
        micCapture?.stop()
        micCapture = nil
        systemCapture?.stop()
        systemCapture = nil
        state.audioLevel = 0
    }

    private func restartCapture() {
        guard state.active else { return }
        stopCapture()
        startCapture()
    }
}

// MARK: - Target language catalog

enum ListenLanguages {
    static let all: [(code: String, name: String)] = [
        ("zh", "中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("pt", "Português"),
    ]

    static func name(for code: String) -> String {
        all.first(where: { $0.code == code })?.name ?? code.uppercased()
    }
}
