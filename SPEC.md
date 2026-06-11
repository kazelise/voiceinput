# VoiceInput 2 — Build Specification

Ground-up rewrite of the VoiceInput menu-bar dictation app for macOS 26+ (designed to feel at home on macOS 27 "Golden Gate"). Native Swift + SwiftUI, Liquid Glass voice box, ChatWise-style settings, Soniox realtime ASR, OpenRouter polish, Ollama translate.

**Read first:** `docs/research/old-app-architecture.md`, `docs/research/soniox-realtime-api.md`, `docs/research/liquid-glass.md`, `docs/research/chatwise-ui-openrouter.md`. Old app source (reference for proven mechanics): `/Users/zhijie/Devs/voice-input-dist/Sources/VoiceInput/`.

## Product behavior

Menu-bar app (NSStatusItem, mic SF Symbol; menu: status line, Enable toggle, "Settings…", "Quit"). No Dock icon (`LSUIElement` = true; activation policy `.accessory` — settings window still works via `NSApp.activate`).

A global hotkey starts a dictation session. Three modes on one key (identical state machine to old app):
- **Hold** (press ≥ 200 ms): push-to-talk; release ends session (with 300 ms forgive window).
- **Toggle** (tap): starts; second tap (or hotkey again) ends.
- **Hands-free** (double-tap): starts; ends on Soniox endpoint/silence (silenceDurationMs) or hotkey.

Session flow:
1. Hotkey down → `DictationController.beginSession(kind:)` → media pause, overlay shows (state `.connecting`), audio capture + ASR session starts.
2. Words stream into the glass voice box live (final + interim styled differently). State `.listening`.
3. End trigger → graceful stop: Soniox `finalize` + empty frame → full final transcript. State `.finalizing`.
4. If polish enabled → OpenRouter; then if translate enabled → Ollama. State `.refining`. Failures fall back to the best text so far (never lose the transcript).
5. Inject text into focused app (clipboard + Cmd-V). State `.injecting` briefly, overlay dismisses, media resumes.
6. Esc anywhere = cancel (discard, no inject). Errors → overlay shows error chip for 2 s, then dismisses.

If transcript is empty/whitespace → no refine, no inject, just dismiss.

## Repo layout & file ownership (one agent per group, NO file overlaps)

```
Package.swift                      (G7)
Makefile                           (G7)
Info.plist                         (G7)
Assets/AppIcon.icns                (already present)
scripts/seed-keys.sh               (G7)
Sources/VoiceInput/
  main.swift                       (G7)
  App/AppDelegate.swift            (G7)
  App/DictationController.swift    (G7)
  App/AppState.swift               (G1)
  Core/AppSettings.swift           (G1)
  Core/VocabularyStore.swift       (G1)
  Core/Log.swift                   (G1)
  Audio/AudioCapture.swift         (G2)
  ASR/TranscriptionTypes.swift     (G2)
  ASR/SonioxRealtimeSession.swift  (G2)
  ASR/HTTPTranscriptionSession.swift (G2)
  Refine/Refiner.swift             (G6)
  System/KeyMonitor.swift          (G3)
  System/TextInjector.swift        (G3)
  System/MediaController.swift     (G3)
  System/PermissionStatus.swift    (G3)
  UI/Theme.swift                   (G5)
  UI/Overlay/OverlayPanel.swift    (G4)
  UI/Overlay/GlassVoiceBox.swift   (G4)
  UI/Overlay/WaveformView.swift    (G4)
  UI/Settings/SettingsWindow.swift (G5)
  UI/Settings/SettingsRootView.swift (G5)
  UI/Settings/Tabs/*.swift         (G5)
  UI/Settings/Controls.swift       (G5)
README.md                          (G8)
```

Build: SPM executable, `platforms: [.macOS("26.0")]`, swift-tools-version 6.0+, `swiftSettings: [.swiftLanguageMode(.v5)]` on the target (port of pre-concurrency AppKit patterns; do NOT fight strict concurrency in this port). Makefile targets `build/run/install/clean`: `swift build -c release`, assemble `VoiceInput.app` bundle (copy binary, Info.plist, AppIcon.icns into Contents/{MacOS,Resources}), ad-hoc `codesign --force --deep -s -`. Port the old repo's Makefile/Info.plist approach; bundle ID **`com.zhijie.VoiceInput`**, app name `VoiceInput`, `LSUIElement` true, `NSMicrophoneUsageDescription`, `NSAppleEventsUsageDescription` (media pause).

## Exact public interfaces (the contract — implement EXACTLY; consumers compile against these)

```swift
// MARK: Core/AppSettings.swift  (G1)
enum ASRBackend: String, CaseIterable { case sonioxRealtime, openAICompatible }
enum TranslateTarget: String, CaseIterable { case english, chineseSimplified, chineseTraditional, korean }
// displayName: String on both enums.

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    // All @Published, persisted to UserDefaults.standard under the listed key, defaults in ().
    @Published var appEnabled: Bool                 // "appEnabled" (true)
    @Published var languageHints: String            // "languageHints" ("zh,en") comma-separated ISO codes
    // Hotkey
    @Published var hotkeyKey: HotkeyKey             // "hotkeyKey" (.fn)
    @Published var customHotkeyKeyCode: Int         // "customHotkeyKeyCode" (24)
    @Published var customHotkeyModifierFlags: Int   // "customHotkeyModifierFlags" (cmd|opt|ctrl|shift rawValue)
    @Published var customHotkeyKeyEquivalent: String// "customHotkeyKeyEquivalent" ("=")
    @Published var tapHoldThresholdMs: Int          // "tapHoldThresholdMs" (200)
    @Published var doublePressWindowMs: Int         // "doublePressWindowMs" (350)
    @Published var holdForgiveMs: Int               // "holdForgiveMs" (300)
    @Published var silenceDurationMs: Int           // "silenceDurationMs" (2500)
    // ASR
    @Published var asrBackend: ASRBackend           // "asrBackend" (.sonioxRealtime)
    @Published var sonioxAPIKey: String             // "sonioxAPIKey" ("")
    @Published var sonioxModel: String              // "sonioxModel" ("stt-rt-v4")
    @Published var httpASRBaseURL: String           // "httpASRBaseURL" ("https://api.openai.com/v1")
    @Published var httpASRAPIKey: String            // "httpASRAPIKey" ("")
    @Published var httpASRModel: String             // "httpASRModel" ("gpt-4o-mini-transcribe")
    // Refinement
    @Published var polishEnabled: Bool              // "polishEnabled" (true)
    @Published var polishBaseURL: String            // "polishBaseURL" ("https://openrouter.ai/api/v1")
    @Published var polishAPIKey: String             // "polishAPIKey" ("")
    @Published var polishModel: String              // "polishModel" ("openai/gpt-oss-120b:free")
    @Published var translateEnabled: Bool           // "translateEnabled" (false)
    @Published var translateTarget: TranslateTarget // "translateTarget" (.english)
    @Published var translateBaseURL: String         // "translateBaseURL" ("http://127.0.0.1:11434/v1")
    @Published var translateAPIKey: String          // "translateAPIKey" ("")
    @Published var translateModel: String           // "translateModel" ("hy-mt2-1.8b-translate:latest")
    // Vocabulary (JSON-encoded [VocabularyEntry])
    @Published var vocabularyJSON: String           // "vocabularyJSON" ("[]")
    // Appearance
    @Published var voiceBoxOpacity: Double          // "voiceBoxOpacity" (0.25)  0 = pure glass, 1 = solid
    @Published var voiceBoxVerticalPosition: Double // "voiceBoxVerticalPosition" (0.62) fraction from screen bottom
    var languageHintsArray: [String] { get }        // parsed, trimmed, lowercased, non-empty
}

// MARK: Core/VocabularyStore.swift  (G1)
struct VocabularyEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var term: String      // canonical, e.g. "Claude Code"
    var hints: String     // common mishearings, comma-separated, e.g. "cloud code, clot code" (may be "")
}
final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()   // loads from AppSettings.shared.vocabularyJSON
    @Published var entries: [VocabularyEntry]   // didSet → save back to vocabularyJSON
    var sonioxTerms: [String] { get }       // non-empty canonical terms
    var promptSection: String { get }       // "" when empty; else lines like: - "cloud code" → "Claude Code"
    func add(_ entry: VocabularyEntry); func remove(at offsets: IndexSet); func update(_ entry: VocabularyEntry)
}

// MARK: Core/Log.swift  (G1)
enum Log {  // os.Logger wrappers, subsystem "com.zhijie.VoiceInput"
    static let app: Logger; static let asr: Logger; static let refine: Logger
    static let audio: Logger; static let keys: Logger; static let ui: Logger
}

// MARK: App/AppState.swift  (G1)
enum DictationPhase: Equatable { case idle, connecting, listening, finalizing, refining, injecting
                                 case error(String) }
struct TranscriptSnapshot: Equatable {
    var finalText: String = ""; var interimText: String = ""
    var combined: String { finalText + interimText }
    var isEmpty: Bool   // combined trimmed empty
}
final class AppState: ObservableObject {     // ALL mutations on main thread
    static let shared = AppState()
    @Published var phase: DictationPhase = .idle
    @Published var transcript = TranscriptSnapshot()
    @Published var audioLevel: Float = 0          // 0...1
    @Published var silenceCountdown: Double? = nil // seconds remaining, hands-free only
    @Published var sessionKind: SessionKind? = nil
}
enum SessionKind { case hold, toggle, handsFree }

// MARK: Audio/AudioCapture.swift  (G2)
final class AudioCapture {
    var onChunk: ((Data) -> Void)?    // 16 kHz mono pcm_s16le, ~100 ms per chunk, background thread
    var onLevel: ((Float) -> Void)?   // normalized RMS 0...1 (formula in old-app report), MAIN thread
    private(set) var sessionWAV: Data // running WAV (16 kHz mono s16le w/ RIFF header) for HTTP backend
    func start() throws               // AVAudioEngine tap at hw format + AVAudioConverter → 16k s16le
    func stop()
}

// MARK: ASR/TranscriptionTypes.swift  (G2)
protocol TranscriptionSession: AnyObject {
    // Callbacks ALL invoked on main thread.
    var onTranscript: ((TranscriptSnapshot) -> Void)? { get set }
    var onUtteranceEnd: (() -> Void)? { get set }   // Soniox <end> token; HTTP backend: never
    var onError: ((String) -> Void)? { get set }
    func start() throws                              // begins capture + recognition
    func stop(completion: @escaping (String) -> Void) // graceful finalize → full final text (falls back to best-known text on error)
    func cancel()                                     // tear down, no callbacks after
    var audioLevelHandler: ((Float) -> Void)? { get set } // re-exposed from AudioCapture, main thread
}
// Factory:
enum TranscriptionFactory {
    static func make(settings: AppSettings, vocabulary: VocabularyStore) -> TranscriptionSession
}

// MARK: ASR/SonioxRealtimeSession.swift  (G2)  — implements TranscriptionSession
// Per docs/research/soniox-realtime-api.md EXACTLY:
// wss://stt-rt.soniox.com/transcribe-websocket; first frame = JSON config {api_key, model,
// audio_format: "pcm_s16le", sample_rate: 16000, num_channels: 1, language_hints,
// enable_language_identification: true, enable_endpoint_detection: true,
// context: {"terms": vocabulary.sonioxTerms} only when non-empty}.
// Binary frames from AudioCapture.onChunk. Accumulate is_final tokens; interim = latest message's
// non-finals only; filter "<end>" (→ onUtteranceEnd) and "<fin>". stop(): send {"type":"finalize"},
// then empty Data() frame, await "finished":true (3 s timeout → use accumulated finals), cancel WS.
// Keepalive {"type":"keepalive"} every 8 s. Generation counter invalidates stale callbacks.
// On WS error mid-session: report via onError but PRESERVE accumulated finals for stop().

// MARK: ASR/HTTPTranscriptionSession.swift  (G2) — implements TranscriptionSession
// Records via AudioCapture only; on stop(): POST multipart {file: session.wav, model, response_format=json,
// language: first languageHint if exactly one} to httpASRBaseURL + "/audio/transcriptions",
// Bearer httpASRAPIKey. Parse {"text": ...}. onTranscript fires once at end. 60 s request timeout.

// MARK: Refine/Refiner.swift  (G6)
final class Refiner {
    init(settings: AppSettings, vocabulary: VocabularyStore)
    func refine(_ text: String, completion: @escaping (String) -> Void)  // main-thread completion.
    // polish (if enabled) → translate (if enabled), sequential. ANY step failure → log + continue
    // with best text so far. Never throws to caller. 30 s timeout per step, single retry on 429
    // honoring Retry-After ≤ 5 s, else skip step.
    func testPolish(completion: @escaping (Result<String, Error>) -> Void)    // round-trips "hello there"
    func testTranslate(completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}
// Polish request (OpenRouter-compatible): POST {polishBaseURL}/chat/completions
// body: {model, messages:[system, user], temperature: 0.3, max_tokens: 2048, stream: false,
//        reasoning: {"effort": "low"}}  ← include reasoning field ONLY when base URL contains "openrouter".
// Headers: Authorization Bearer, HTTP-Referer: https://github.com/zhijie/voiceinput, X-Title: VoiceInput.
// Polish system prompt: rebuild old app's structure (see old-app-architecture.md "Old pipeline"):
//   role → TASK (clean disfluencies/fillers/repeats/false starts/punctuation/grammar; preserve meaning,
//   tone, source language; do not translate; keep natural zh/en mix) → DICTATION CONTEXT (developer
//   dictating while coding on macOS; zh/en mixed) → ASR CORRECTION (smallest correction; homophone
//   repair) → VOCABULARY (VocabularyStore.promptSection: "If the transcript contains something like the
//   left side, the speaker almost certainly meant the right side:" + lines) → PRESERVE VERBATIM (brands,
//   code identifiers, paths, URLs, CLI, acronyms) → OUTPUT: only the text, no quotes/framing.
// Translate request: same endpoint shape vs translateBaseURL/Model, temperature 0.1, no reasoning field.
// Translate system prompt: translation engine; target = translateTarget phrase; output only translation;
// preserve technical identifiers verbatim.
// Parse choices[0].message.content (ignore .reasoning). Strip wrapping quotes/whitespace.

// MARK: System/*  (G3) — direct ports from old app (read its source!), same public surface:
enum HotkeyKey: String, CaseIterable { case fn, rightCommand, rightOption, rightShift, rightControl, customShortcut }
struct HotkeyShortcut: Equatable { var keyCode: UInt16; var modifierFlags: NSEvent.ModifierFlags; var keyEquivalent: String
                                   var displayString: String { get } }
final class KeyMonitor {
    var onStart: ((SessionKind) -> Void)?; var onStop: (() -> Void)?
    func configure(key: HotkeyKey, customShortcut: HotkeyShortcut?,
                   tapHoldThresholdMs: Int, doublePressWindowMs: Int, holdForgiveMs: Int)
    func start(); func stop()
}
final class TextInjector { func inject(_ text: String) }   // clipboard + IME-aware Cmd-V (old algorithm verbatim)
final class MediaController { func pauseIfPlaying(); func resumeIfPaused() }
final class PermissionStatus: ObservableObject {
    static let shared = PermissionStatus()
    enum State { case granted, notDetermined, denied }
    @Published var microphone: State; @Published var accessibility: State
    func refresh(); func grantMicrophone(); func grantAccessibility()
    var allGranted: Bool { get }
}

// MARK: UI/Theme.swift  (G5) — ChatWise palette (chatwise-ui-openrouter.md), light/dark adaptive:
enum Theme {
    static let accent: Color            // #4E80EE light / #2464EB dark
    static let contentBackground: Color // #FFFFFF / #222125
    static let sidebarBackground: Color // #F2EDEC / #28272B
    static let chrome: Color            // #EFEFF4 / #222125
    static let pill: Color              // #E4E4E7 / #3F3F46
    static let fieldFill: Color         // #F4F4F5 / #343337
    static let hairline: Color          // #E4E4E7 / #3F3F46
    static let textPrimary: Color       // #0A0A0B / #F9F9F9
    static let textSecondary: Color     // #707074 / #96969C
    // implement via Color(nsColor: NSColor(name:dynamicProvider:)) for automatic appearance switching
}

// MARK: UI/Overlay/OverlayPanel.swift  (G4)
final class OverlayPanel {
    init(state: AppState, settings: AppSettings)
    var onStop: (() -> Void)?; var onCancel: (() -> Void)?
    func show()      // on screen containing mouse pointer; non-activating
    func dismiss()
    func updateHotkeyLabel(_ display: String)
}

// MARK: UI/Settings/SettingsWindow.swift  (G5)
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    func show()   // creates/reuses NSWindow (640×560 min), NSHostingView(SettingsRootView), activates app
}
```

## The Liquid Glass voice box (G4) — the centerpiece

Implementation rules come from `docs/research/liquid-glass.md`. NSPanel: borderless, `.nonactivatingPanel`, floating level, transparent (`isOpaque=false`, `backgroundColor=.clear`), shadow off (SwiftUI draws its own), `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`, hosts `NSHostingView(GlassVoiceBox(...))`. Position: centered X, `voiceBoxVerticalPosition` (default 62%) from bottom, on the screen containing the mouse. Esc global+local monitor while visible → onCancel.

GlassVoiceBox (SwiftUI):
- Container: `GlassEffectContainer`. Box: width 680, RoundedRectangle(cornerRadius: 28, style: .continuous).
- **Glass + adjustable transparency (Approach B from research)**: `Color.clear.glassEffect(.regular, in: shape)` base layer + scrim `shape.fill(Color(nsColor: .windowBackgroundColor).opacity(voiceBoxOpacity))` on top, content above. At opacity ≥ 0.99 drop glass layer. Respect `accessibilityReduceTransparency` → force opaque.
- **kube.io-inspired rim**: 1.5 pt stroke of the shape with an AngularGradient brightest near the 60° light direction (white 0.5 → 0.05 opacity), plus a second inner hairline (white 0.12). Subtle — accent, not outline.
- Layout (top→bottom): live transcript area (min 1, max 3 lines, 17 pt medium, finalText in primary color + interimText in secondary 60% opacity with a soft shimmer/fade-in; placeholder "Listening…" / "连接中…" per phase, secondary color, when empty) → waveform (centered, full width, height 34) → bottom bar.
- Waveform (WaveformView): SwiftUI `Canvas` + TimelineView, ~72 rolling bars, 3 pt wide / 2.5 pt gap, rounded caps, symmetric about centerline, colored `Theme.accent` gradient at 0.9 opacity, driven by `state.audioLevel` history; gentle idle breathing when level ≈ 0.
- Bottom bar: left = phase indicator (8 pt dot: accent pulsing while listening, yellow finalizing, purple refining + label "Listening / Finalizing / Polishing / Translating…") + hands-free countdown pill ("2.5s") when `silenceCountdown != nil` + chips "Polish" / "Translate EN|简|繁|KO" (small gray pills, accent-tinted when enabled). Right = "Stop ⏎-style hotkey badge" and "Cancel esc" — text buttons with `.glassEffect(.regular.interactive(), in: .capsule)` so the buttons are tiny glass elements within the container (use `glassEffectID` so show/hide morphs).
- Phase transitions animate with `.spring(duration: 0.35)`; panel show/dismiss: scale 0.97→1 + fade, 0.25 s.
- Error phase: box border flashes red-tinted scrim, error text in transcript area, auto-dismiss after 2 s.

## Settings window (G5) — ChatWise style

Per `chatwise-ui-openrouter.md`. NSWindow, hidden title ("Settings" drawn in-content, centered, bold 15 pt), `titlebarAppearsTransparent`, full-size content. Top: horizontal icon-tab strip — tabs **General, Hotkey, Providers, Vocabulary, Appearance, Permissions** — SF Symbols line icons (gear, command, server.rack, character.book.closed, sparkles, lock.shield) above 12 pt labels; selected = `Theme.pill` rounded pill + `Theme.accent` tint. Hairline below. Window background `Theme.chrome`; content cards `Theme.contentBackground` rounded 10 with hairline border.

Form idiom (Controls.swift): rows with 13 pt semibold label + 12 pt secondary helper text UNDER the label; filled rounded text fields (`Theme.fieldFill`, radius 8, hairline border); blue toggles right-aligned; SecureField for API keys with show/hide eye button; "Test" buttons (`.bordered`) next to polish/translate with inline ✓/✗ result text.

Tabs:
- **General**: enable toggle; language hints field (comma-separated, helper "ISO codes, e.g. zh,en — passed to Soniox as language_hints").
- **Hotkey**: key picker (Fn/Right ⌘/Right ⌥/Right ⇧/Right ⌃/Custom); custom → shortcut recorder button (port old recorder); collapsible "Timing" group with steppers for the four ms values; explainer card describing hold/tap/double-tap modes.
- **Providers**: ChatWise-style master-detail. Source list (170 pt): "Soniox Realtime", "OpenAI-compatible ASR", "Polish · OpenRouter", "Translate · Ollama" with status dot (green if key/URL configured). Detail pane: relevant fields (backend picker for the ASR pair sits at top of both ASR pages: "Active backend"); Soniox page = API key + model; HTTP ASR = base URL + key + model; Polish = enable toggle, base URL, key, model, Test; Translate = enable toggle, target language picker, base URL, key, model, Test.
- **Vocabulary**: explainer ("Terms sent to Soniox for recognition biasing and used by polish to fix mishearings — e.g. 'cloud code' → 'Claude Code'"); table of entries (term + mishearings columns, inline editable), +/- buttons bottom-left ChatWise style; entries persist via VocabularyStore.
- **Appearance**: voice-box transparency slider 0–100% with live percent label (helper: "0% = clear liquid glass, 100% = solid"); vertical position slider 30–90%; "Preview voice box" button → shows overlay with sample transcript for 4 s (wire via callback to AppDelegate through NotificationCenter `Notification.Name("VoiceInputPreviewOverlay")`).
- **Permissions**: rows for Microphone + Accessibility (icon, title, status, Grant/Open Settings button), mirroring old app logic.

## Orchestration (G7)

`DictationController` owns: AudioCapture-backed TranscriptionSession (created per session via TranscriptionFactory), Refiner, TextInjector, MediaController, OverlayPanel, and writes AppState. Hands-free: silence countdown driven by Soniox `onUtteranceEnd` + last-transcript-change timestamps checked every 250 ms (countdown into `AppState.silenceCountdown`). Guard re-entrancy: ignore beginSession while active; endSession idempotent. `AppDelegate`: status item + menu, permissions on launch, KeyMonitor wiring + re-wire on settings change (Combine, debounced 300 ms), preview-overlay notification listener, settings window. main.swift: NSApplication boot, `.accessory` policy.

`scripts/seed-keys.sh`: reads `.env.local`, `defaults write com.zhijie.VoiceInput sonioxAPIKey/polishAPIKey ...`, prints confirmation. Never store keys in source or git.

## Non-negotiables

1. Callbacks crossing into UI/state land on the main thread. AppState mutations main-thread only.
2. Generation counter pattern (old app) for all async session callbacks — no stale-session bleed.
3. Transcript is sacred: any failure after speech ends still injects the best available text (unless cancelled).
4. CGEventTap re-enable on `.tapDisabledByTimeout/.tapDisabledByUserInput`.
5. `@available(macOS 26.0, *)` not needed anywhere — min deployment IS 26.0.
6. No third-party dependencies. AppKit+SwiftUI+Foundation+AVFoundation+Carbon(TIS) only.
7. Swift language mode v5 in Package.swift; code must compile with zero errors AND zero warnings under `swift build -c release`.
8. Match ChatWise palette via Theme — never raw system grays in settings UI.
