import Foundation

/// A live-captions engine: streams audio in, emits original-language and
/// translated text out. Two implementations — `SonioxListenSession` (one
/// Soniox WebSocket with one-way translation) and `GeminiListenSession`
/// (Gemini Live API: input transcription + translated model output).
///
/// All callbacks are delivered on the main thread.
protocol LiveCaptionSession: AnyObject {
    /// Original-language transcript (left column). A provider that cannot
    /// surface the source transcription simply never calls this.
    var onOriginal: ((TranscriptSnapshot) -> Void)? { get set }
    /// Translated transcript (right column / caption bar).
    var onTranslation: ((TranscriptSnapshot) -> Void)? { get set }
    /// Fired once the stream is live and ready for audio.
    var onConnected: (() -> Void)? { get set }
    /// Non-recoverable error (auth, network, quota).
    var onError: ((String) -> Void)? { get set }

    /// Open the stream using the current settings (target language, model, keys).
    func start(settings: AppSettings)
    /// Feed 16 kHz mono s16le audio (any thread).
    func sendAudio(_ data: Data)
    /// Tear down; no further callbacks.
    func stop()
}

// MARK: - Factory

enum LiveCaptionFactory {
    static func make(settings: AppSettings) -> LiveCaptionSession {
        switch settings.liveCaptionProvider {
        case .soniox: return SonioxListenSession()
        case .gemini: return GeminiListenSession()
        }
    }
}
