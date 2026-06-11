import os.log

// MARK: - Log

/// Centralised os.Logger channels for the VoiceInput app.
/// Subsystem: "com.zhijie.VoiceInput"
enum Log {
    private static let subsystem = "com.zhijie.VoiceInput"

    /// General application / lifecycle events.
    static let app    = Logger(subsystem: subsystem, category: "app")

    /// ASR / transcription session events.
    static let asr    = Logger(subsystem: subsystem, category: "asr")

    /// LLM refinement (polish / translate) events.
    static let refine = Logger(subsystem: subsystem, category: "refine")

    /// Audio capture / AVAudioEngine events.
    static let audio  = Logger(subsystem: subsystem, category: "audio")

    /// Global hotkey / KeyMonitor events.
    static let keys   = Logger(subsystem: subsystem, category: "keys")

    /// Overlay / settings UI events.
    static let ui     = Logger(subsystem: subsystem, category: "ui")
}
