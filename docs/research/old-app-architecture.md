# Old VoiceInput App — Architecture Reference

*Report on `/Users/zhijie/Devs/voice-input-dist` (the app being rewritten). Swift 5.9, AppKit, SPM, menu-bar app, ~4,200 lines. The rewrite keeps the proven mechanics (hotkey state machine, text injection, media control) and replaces ASR/UI/post-processing.*

## Overview

Menu-bar voice-input app: captures speech via global hotkey, transcribes (OpenAI Realtime WS or local HTTP ASR), optionally polishes/translates via LLM, injects result into focused app via clipboard+Cmd-V. Three hotkey interaction modes on a single key: hold (push-to-talk), toggle (tap), hands-free (double-tap, ends on silence).

## Source files

| File | Lines | Responsibility |
|---|---|---|
| main.swift | 8 | NSApplication entry, sets AppDelegate |
| AppDelegate.swift | 419 | Orchestration: session lifecycle, hotkey wiring, callbacks |
| AppSettings.swift | 315 | UserDefaults-backed settings singleton, all @Published |
| KeyMonitor.swift | 541 | Global hotkey, CGEventTap + NSEvent, hold/tap/double-tap state machine |
| SpeechEngine.swift | 950 | AVAudioEngine capture + OpenAI Realtime WS / local HTTP ASR |
| LLMRefiner.swift | 350 | Polish → Translate chained chat-completions calls |
| TextInjector.swift | 76 | Clipboard + synthetic Cmd-V injection, IME-aware |
| MediaController.swift | 163 | Pause/resume Spotify/Music/MediaRemote during recording |
| OverlayPanel.swift | 704 | Floating HUD: waveform, transcript, status, buttons |
| PermissionStatus.swift | 76 | Mic + Accessibility permission tracking |
| MainWindow.swift | 638 | SwiftUI settings window in NSWindow |

## Key mechanics worth carrying over

### Hotkey state machine (KeyMonitor)
- `HotkeyKey` enum: `.fn`, `.rightCommand`, `.rightOption`, `.rightShift`, `.rightControl`, `.customShortcut`.
- Fn key: CGEventTap on `.flagsChanged`, checks `.maskSecondaryFn`, returns nil to suppress. Custom shortcut: tap on `.keyDown/.keyUp/.flagsChanged`. NSEvent global+local monitors as fallback for non-Fn keys.
- Tap installed at `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`. Must handle `.tapDisabledByTimeout`/`.tapDisabledByUserInput` by re-enabling.
- State machine: idle → keyDown → holdOrTapPending (timer tapHoldThresholdMs=200) → hold fires `.hold` start; keyUp before threshold → waitingSecondTap (doublePressWindowMs=350) → timeout fires `.toggle`; second tap within window → `.handsFree`. In hold mode, keyUp starts forgive timer (holdForgiveMs=300) tolerating brief release.
- Hands-free ends on silence: timer checks every 250 ms whether last speech token older than silenceDurationMs (default 2500); countdown badge callback.
- Custom shortcut recording: NSButton subclass monitors local .keyDown, requires ≥1 modifier, Esc cancels, stores keyCode+modifierFlags+keyEquivalent. Default: keyCode 24 (=), ⌘⌥⌃⇧.

### Text injection (TextInjector)
1. Write text to `NSPasteboard.general`.
2. If current TIS input source not ASCII-capable: switch to com.apple.keylayout.ABC/US, wait 50 ms.
3. Synthesize Cmd+V: `CGEvent(keyboardEventSource:virtualKey: 0x09, keyDown:)` with `.maskCommand`, post to `.cgAnnotatedSessionEventTap`.
4. Restore original input source after 300 ms. Keep text on clipboard as fallback.
- Requires Accessibility permission. Uses Carbon TIS APIs: `TISCopyCurrentKeyboardInputSource`, `TISSelectInputSource`, `kTISPropertyInputSourceIsASCIICapable`, `TISCreateInputSourceList`.

### Audio capture (SpeechEngine)
- `AVAudioEngine`, input tap bufferSize 1024 at hardware format (typically 48 kHz). Float samples from `floatChannelData[0]`.
- Audio level for waveform: RMS → `(20*log10(max(rms,1e-6))+50)/40` clipped to [0,1].
- Generation counter (`UInt64`) invalidates stale async callbacks across sessions — essential pattern, keep it.

### Media control (MediaController)
- Priority: Spotify (AppleScript) → Apple Music (AppleScript) → MRMediaRemote private framework (dlopen, best-effort, likely no-op on modern macOS).
- Checks `NSWorkspace.runningApplications` bundle ID before AppleScript. `didPauseMedia` flag so resume only undoes actual pauses.
- Requires `NSAppleEventsUsageDescription`.

### Permissions (PermissionStatus)
- Microphone: `AVCaptureDevice.authorizationStatus(for: .audio)` / `requestAccess`.
- Accessibility: `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions(prompt: true)`.
- Re-probe on app activation. Info.plist: `NSMicrophoneUsageDescription`, `NSAppleEventsUsageDescription`.

## Old overlay panel (being redesigned, dimensions for reference)
- NSPanel 640×136 pt, borderless, floating, non-activating; `.hudWindow` NSVisualEffectView, dark; corner radius 20; faux-glass via 3 gradient layers (depth/specular/rim); positioned screen-center-X at 62% from bottom.
- DenseWaveformView: 90 bars × 3 pt + 2 pt gap, symmetric around centerline, driven by audio level.
- Action bar: status dot (blue listening / yellow transcribing / purple processing) + label + countdown badge + polish/translate chips | Stop + hotkey badge, Cancel + Esc badge.
- Esc global monitor while visible → cancel.

## Old pipeline (being replaced)
- ASR: OpenAI Realtime WS (`wss://api.openai.com/v1/realtime?intent=transcription`, session.update with audio/pcm 24kHz, input_audio_buffer.append base64 chunks, transcription delta/completed events) OR local HTTP multipart WAV to `/v1/audio/transcriptions` ({"text": ...} response). The OpenAI-compatible HTTP transcription path is worth keeping as the secondary backend (works with api.openai.com and any compatible server).
- Polish/Translate (LLMRefiner): two independent OpenAI-compatible `/chat/completions` endpoints, sequential chaining (polish output → translate input), `stream: false`, temp 0.3 polish / 0.1 translate, parse `choices[0].message.content`.
- Translate default: Ollama `http://127.0.0.1:11434/v1`, model `hy-mt2-1.8b-translate:latest` — KEEP THIS.
- Old polish prompt structure (rebuild on this skeleton): role statement; TASK (clean disfluencies/fillers/repeats/false starts/punctuation/grammar; preserve meaning+tone+source language; don't translate; keep zh/en mix natural); DICTATION CONTEXT (developer dictating notes while coding on macOS, zh/en mixed, preferred tech-term list); ASR CORRECTION (repair likely homophone errors using context, smallest correction, e.g. "备份"→"build", "重写"→"重启"); PRESERVE VERBATIM (brands, code identifiers, paths, URLs, CLI, acronyms); OUTPUT (only the text, no framing/quotes).
- Translate prompt: translation engine role; target language phrase; don't answer/summarize; same preserve-verbatim + output rules.

## Old UserDefaults keys (for reference; new app uses its own domain)

appEnabled, selectedLocaleCode, speechBackend (openAIRealtime|localHTTP), openAISttAPIKey, sttModel, localASRBaseURL, localASRAPIKey, localASRModel, llm* (legacy), polishAPIBaseURL (default http://localhost:8317/v1), polishAPIKey, polishModel, translateAPIBaseURL (default http://127.0.0.1:11434/v1), translateAPIKey, translateModel (hy-mt2-1.8b-translate:latest), polishEnabled, translateEnabled, translateTarget (english|chineseSimplified|chineseTraditional|korean), hotkeyKey, customHotkeyKeyCode (24), customHotkeyModifierFlags, customHotkeyKeyEquivalent ("="), tapHoldThresholdMs (200), holdForgiveMs (300), doublePressWindowMs (350), silenceDurationMs (2500), customVocabulary.

## Settings window (old, being redesigned)
- 560×760 NSWindow + NSHostingView, frame autosave "VoiceInputMainWindow".
- Sections: Header | Status card | General (enable toggle, language picker: Auto/en-US/zh-CN/zh-TW/ja-JP/ko-KR) | Hotkey (key picker, shortcut recorder, timing steppers) | Speech Recognition (backend picker, key/model fields, vocabulary TextEditor) | Post-processing (polish toggle+fields+test btn, translate toggle+target+fields+test btn) | Permissions (mic + accessibility rows).

## Fragile parts / lessons (avoid repeating)

1. CGEventTap can be disabled by timeout — must detect `.tapDisabledByTimeout` and re-enable (old app does; keep).
2. Input-source switching in TextInjector is timing-dependent (50/300 ms sleeps) — works but keep delays.
3. Silence detection driven by transcript-token arrival, not audio VAD — with Soniox endpoint detection (`<end>` token + `enable_endpoint_detection`) this gets much better; prefer Soniox endpointing for hands-free stop.
4. No WS reconnection — new app should keep accumulated finals and reconnect once on unexpected drop.
5. `NSScreen.main` positioning breaks on multi-monitor changes — prefer screen with mouse/key window.
6. AppDelegate does too much — split orchestration into a session controller.
7. File logging ad-hoc — use os.log (Logger) in rewrite.
8. Singletons everywhere — acceptable for an app this size, but keep them few: Settings, AppState.
9. MRMediaRemote private framework likely no-op now — keep AppleScript paths, treat MediaRemote as best-effort.
10. Manual WAV encoding was hand-rolled — fine, small; or use AVAudioFile.
