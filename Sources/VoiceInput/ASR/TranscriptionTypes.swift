import Foundation

// MARK: - TranscriptionSession protocol

/// Common interface for all ASR backends (Soniox Realtime WebSocket and HTTP batch).
/// All callbacks are guaranteed to be invoked on the **main thread**.
protocol TranscriptionSession: AnyObject {
    // MARK: Callbacks (main thread)

    /// Fires whenever the transcript snapshot changes. Both finals and interims
    /// are included; see `TranscriptSnapshot` for the combined accessor.
    var onTranscript: ((TranscriptSnapshot) -> Void)? { get set }

    /// Fires when Soniox emits an `<end>` endpoint-detection token. The HTTP
    /// backend never fires this (it has no streaming tokens).
    var onUtteranceEnd: (() -> Void)? { get set }

    /// Fires when a non-recoverable error occurs. The session preserves any
    /// accumulated finals so that `stop(completion:)` can still return them.
    var onError: ((String) -> Void)? { get set }

    // MARK: Audio level passthrough (main thread)

    /// Re-exposed from the underlying `AudioCapture`; set before calling `start()`.
    var audioLevelHandler: ((Float) -> Void)? { get set }

    // MARK: Captured audio

    /// The session's captured microphone audio as a complete 16 kHz mono WAV,
    /// or `nil` if nothing was captured. Intended to be read once at session
    /// end (after `stop`/`cancel` has run, or just before) so dictation history
    /// can persist the audio. Materialising the WAV is deferred until this is
    /// read, so callers that don't keep audio pay nothing.
    var capturedAudioWAV: Data? { get }

    // MARK: Lifecycle

    /// Attach to microphone and begin recognition. Throws on audio-engine failure.
    func start() throws

    /// Gracefully finalize in-flight audio, collect the full final transcript,
    /// and call `completion` on the main thread with the best available text.
    /// Falls back to accumulated finals on timeout or WebSocket error.
    func stop(completion: @escaping (String) -> Void)

    /// Immediately tear down audio and networking. No further callbacks are fired.
    func cancel()
}

// MARK: - TranscriptionFactory

/// Creates the appropriate `TranscriptionSession` based on the current settings.
enum TranscriptionFactory {
    static func make(settings: AppSettings, vocabulary: VocabularyStore) -> TranscriptionSession {
        switch settings.asrBackend {
        case .sonioxRealtime:
            return SonioxRealtimeSession(settings: settings, vocabulary: vocabulary)
        case .openAICompatible:
            return HTTPTranscriptionSession(settings: settings, vocabulary: vocabulary)
        }
    }
}
