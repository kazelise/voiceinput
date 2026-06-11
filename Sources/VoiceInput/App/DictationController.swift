import AppKit
import Combine
import os.log

// MARK: - DictationController

/// Owns the session lifecycle: audio capture → ASR → refine → inject.
/// All AppState mutations are dispatched to the main thread.
/// AppDelegate wires KeyMonitor callbacks into beginSession/endSession/cancelSession.
final class DictationController {

    // MARK: - External callbacks (wired by AppDelegate)

    /// Called when a session ends by a path other than a user hotkey tap
    /// (hands-free silence auto-stop, overlay Stop button).
    /// AppDelegate wires this to keyMonitor.externalStop().
    var onSessionEndedExternally: (() -> Void)?

    /// Called when a session is cancelled (Esc / overlay Cancel / app-disabled).
    /// AppDelegate wires this to keyMonitor.reset().
    var onSessionCancelled: (() -> Void)?

    // MARK: - Dependencies

    private let settings: AppSettings
    private let appState: AppState
    private let refiner: Refiner
    private let textInjector: TextInjector
    private let mediaController: MediaController
    private let overlayPanel: OverlayPanel

    // MARK: - Session state

    private var session: TranscriptionSession?
    private var sessionGeneration: UInt64 = 0
    private var isActive: Bool = false
    private var bestTranscript: String = ""

    // Hands-free silence countdown
    private var silenceTimer: Timer?
    private var lastTranscriptChangeDate: Date?
    private var utteranceEndFired: Bool = false

    // Preview overlay state
    private var previewTimer: Timer?

    // MARK: - Init

    init(settings: AppSettings,
         appState: AppState,
         refiner: Refiner,
         textInjector: TextInjector,
         mediaController: MediaController,
         overlayPanel: OverlayPanel) {
        self.settings = settings
        self.appState = appState
        self.refiner = refiner
        self.textInjector = textInjector
        self.mediaController = mediaController
        self.overlayPanel = overlayPanel

        overlayPanel.onStop = { [weak self] in
            self?.endSession()
        }
        overlayPanel.onCancel = { [weak self] in
            self?.cancelSession()
        }
    }

    // MARK: - Public API

    /// Forward the hotkey display label to the overlay panel.
    func updateHotkeyLabel(_ display: String) {
        overlayPanel.updateHotkeyLabel(display)
    }

    /// Begin a dictation session. Re-entrancy guard: ignored if a session is already active.
    func beginSession(kind: SessionKind) {
        guard !isActive else {
            Log.app.debug("beginSession ignored — session already active")
            return
        }
        isActive = true
        // A preview overlay may still be counting down; cancel it so its 4 s
        // callback can't tear down the overlay/AppState mid-session.
        previewTimer?.invalidate()
        previewTimer = nil
        bestTranscript = ""
        sessionGeneration &+= 1
        let generation = sessionGeneration

        Log.app.info("beginSession kind=\(String(describing: kind))")

        // Pause media before touching audio hardware.
        mediaController.pauseIfPlaying()

        // Update state to connecting immediately.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.phase = .connecting
            self.appState.transcript = TranscriptSnapshot()
            self.appState.audioLevel = 0
            self.appState.silenceCountdown = nil
            self.appState.sessionKind = kind
        }

        overlayPanel.show()

        // Create ASR session.
        let vocabulary = VocabularyStore.shared
        let asrSession = TranscriptionFactory.make(settings: settings, vocabulary: vocabulary)
        session = asrSession

        // Wire callbacks.
        asrSession.audioLevelHandler = { [weak self] level in
            // Already on main (per contract).
            self?.appState.audioLevel = level
        }

        asrSession.onTranscript = { [weak self] snapshot in
            guard let self else { return }
            guard self.sessionGeneration == generation else { return }
            // Already on main (per contract).
            let wasEmpty = self.appState.transcript.isEmpty
            self.appState.transcript = snapshot
            self.bestTranscript = snapshot.combined

            // Track last change timestamp for silence countdown.
            if !snapshot.combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.lastTranscriptChangeDate = Date()
            }

            // Arm silence countdown only for hands-free + Soniox (incremental) backend.
            if kind == .handsFree &&
               self.settings.asrBackend == .sonioxRealtime &&
               (wasEmpty || self.silenceTimer == nil) {
                self.armSilenceCountdown()
            }
        }

        asrSession.onUtteranceEnd = { [weak self] in
            guard let self else { return }
            guard self.sessionGeneration == generation else { return }
            // Already on main (per contract).
            if kind == .handsFree && self.settings.asrBackend == .sonioxRealtime {
                self.utteranceEndFired = true
                self.lastTranscriptChangeDate = Date()
                self.armSilenceCountdown()
            }
        }

        asrSession.onError = { [weak self] errorMessage in
            guard let self else { return }
            guard self.sessionGeneration == generation else { return }
            // Already on main (per contract).
            Log.asr.error("ASR error: \(errorMessage)")
            self.appState.phase = .error(errorMessage)
            // After 2 s dismiss and recover.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                guard self.sessionGeneration == generation else { return }
                self.overlayPanel.dismiss()
                self.mediaController.resumeIfPaused()
                self.appState.phase = .idle
                self.appState.silenceCountdown = nil
                self.appState.sessionKind = nil
                self.isActive = false
                self.session = nil
                self.teardownSilenceTimer()
                self.onSessionEndedExternally?()
            }
        }

        // Transition to listening.
        DispatchQueue.main.async { [weak self] in
            self?.appState.phase = .listening
        }

        do {
            try asrSession.start()
        } catch {
            Log.asr.error("ASR start error: \(error)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.appState.phase = .error(error.localizedDescription)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    self.overlayPanel.dismiss()
                    self.mediaController.resumeIfPaused()
                    self.appState.phase = .idle
                    self.appState.sessionKind = nil
                    self.isActive = false
                    self.session = nil
                    self.onSessionEndedExternally?()
                }
            }
        }
    }

    /// Graceful stop: finalize ASR → refine → inject.
    /// Idempotent if called multiple times.
    func endSession() {
        guard isActive else {
            Log.app.debug("endSession ignored — no active session")
            return
        }
        // Mark inactive immediately so any re-entrant endSession()/cancelSession()
        // (e.g. overlay Stop racing the hands-free silence auto-stop) hits the
        // guard above and returns, rather than calling asrSession.stop() twice.
        isActive = false
        Log.app.info("endSession")
        teardownSilenceTimer()
        let generation = sessionGeneration

        DispatchQueue.main.async { [weak self] in
            self?.appState.phase = .finalizing
            self?.appState.silenceCountdown = nil
        }

        guard let asrSession = session else {
            // No ASR session — just clean up.
            finishAfterTranscript(text: bestTranscript, generation: generation, externallyEnded: true)
            return
        }

        asrSession.stop { [weak self] finalText in
            guard let self else { return }
            guard self.sessionGeneration == generation else { return }
            // stop(completion:) delivers on main thread per contract.
            let text = finalText.isEmpty ? self.bestTranscript : finalText
            self.finishAfterTranscript(text: text, generation: generation, externallyEnded: true)
        }
    }

    /// Cancel: discard transcript, do not inject.
    /// Idempotent.
    func cancelSession() {
        guard isActive else {
            Log.app.debug("cancelSession ignored — no active session")
            return
        }
        Log.app.info("cancelSession")
        teardownSilenceTimer()
        let capturedSession = session
        isActive = false
        session = nil
        sessionGeneration &+= 1   // Invalidate any in-flight callbacks.

        capturedSession?.cancel()
        refiner.cancel()
        overlayPanel.dismiss()
        mediaController.resumeIfPaused()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.phase = .idle
            self.appState.transcript = TranscriptSnapshot()
            self.appState.silenceCountdown = nil
            self.appState.sessionKind = nil
        }
        onSessionCancelled?()
    }

    // MARK: - Preview overlay

    /// Show a sample transcript in the overlay for 4 seconds.
    /// Ignored while a real session is active.
    func showPreviewOverlay() {
        guard !isActive else {
            Log.app.debug("showPreviewOverlay ignored — session active")
            return
        }

        // Cancel any existing preview.
        previewTimer?.invalidate()
        previewTimer = nil

        let sampleFinal = "Voice input makes coding faster. "
        let sampleInterim = "It streams text in real time."
        let snapshot = TranscriptSnapshot(finalText: sampleFinal, interimText: sampleInterim)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.phase = .listening
            self.appState.transcript = snapshot
            self.appState.audioLevel = 0.4
            self.appState.sessionKind = .toggle
            self.overlayPanel.show()
        }

        previewTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            // A real session may have started since this timer was scheduled; if
            // so, leave its overlay/AppState untouched.
            guard !self.isActive else { self.previewTimer = nil; return }
            DispatchQueue.main.async {
                self.overlayPanel.dismiss()
                self.appState.phase = .idle
                self.appState.transcript = TranscriptSnapshot()
                self.appState.audioLevel = 0
                self.appState.sessionKind = nil
            }
            self.previewTimer = nil
        }
    }

    // MARK: - Hands-free silence countdown

    private func armSilenceCountdown() {
        // Only relevant for hands-free + Soniox.
        guard appState.sessionKind == .handsFree,
              settings.asrBackend == .sonioxRealtime else { return }

        // If a timer is already running, let it keep ticking.
        if silenceTimer != nil { return }

        lastTranscriptChangeDate = Date()

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tickSilenceCountdown()
        }
    }

    private func tickSilenceCountdown() {
        guard isActive, appState.sessionKind == .handsFree else {
            teardownSilenceTimer()
            return
        }

        let silenceDuration = Double(settings.silenceDurationMs) / 1000.0

        // Only count down after utterance end has fired or some transcript arrived.
        guard utteranceEndFired || lastTranscriptChangeDate != nil else { return }

        let reference = lastTranscriptChangeDate ?? Date()
        let elapsed = Date().timeIntervalSince(reference)
        let remaining = max(0.0, silenceDuration - elapsed)

        // tickSilenceCountdown() is the body of a main-thread RunLoop Timer, so
        // this mutation is already on the main thread — assign directly so the
        // countdown display stays in lockstep with the remaining <= 0 check below.
        appState.silenceCountdown = remaining

        if remaining <= 0 {
            Log.app.info("Hands-free silence elapsed — auto-ending session")
            teardownSilenceTimer()
            // endSession() runs with externallyEnded: true, so it already fires
            // onSessionEndedExternally?() (→ keyMonitor.externalStop()) once the
            // pipeline completes. Calling it here too would reset KeyMonitor early
            // (before the controller is done) and fire it twice.
            endSession()
        }
    }

    private func teardownSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        utteranceEndFired = false
        lastTranscriptChangeDate = nil
    }

    // MARK: - Post-ASR pipeline

    /// Called on main thread after ASR finalization.
    private func finishAfterTranscript(text: String, generation: UInt64, externallyEnded: Bool) {
        // Mark session as no longer active so endSession/cancelSession are no-ops.
        isActive = false
        session = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            // Nothing to inject.
            Log.app.info("Empty transcript — dismissing without inject")
            overlayPanel.dismiss()
            mediaController.resumeIfPaused()
            appState.phase = .idle
            appState.transcript = TranscriptSnapshot()
            appState.silenceCountdown = nil
            appState.sessionKind = nil
            if externallyEnded { onSessionEndedExternally?() }
            return
        }

        let needsRefine = settings.polishEnabled || settings.translateEnabled

        if needsRefine {
            appState.phase = .refining

            refiner.refine(trimmed) { [weak self] refined in
                guard let self else { return }
                guard self.sessionGeneration == generation else { return }
                // refiner completion is on main thread.
                let finalText = refined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? trimmed : refined
                self.injectAndFinish(text: finalText, generation: generation, externallyEnded: externallyEnded)
            }
        } else {
            injectAndFinish(text: trimmed, generation: generation, externallyEnded: externallyEnded)
        }
    }

    private func injectAndFinish(text: String, generation: UInt64, externallyEnded: Bool) {
        appState.phase = .injecting

        // Brief injecting state for visual feedback, then inject.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            guard self.sessionGeneration == generation else { return }

            self.textInjector.inject(text)
            self.overlayPanel.dismiss()
            self.mediaController.resumeIfPaused()
            self.appState.phase = .idle
            self.appState.transcript = TranscriptSnapshot()
            self.appState.silenceCountdown = nil
            self.appState.sessionKind = nil

            if externallyEnded {
                self.onSessionEndedExternally?()
            }
        }
    }
}
