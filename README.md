# VoiceInput 2

A native macOS 26+ menu-bar dictation app featuring real-time speech-to-text, LLM-powered text refinement, and vocabulary-aware transcription. Designed for Golden Gate with Liquid Glass aesthetics.

## What is VoiceInput?

VoiceInput is a voice-input companion for macOS developers and writers. Activate it with a customizable global hotkey (default: Fn key) to dictate hands-free, and it transcribes your words in real time, polishes the text with an LLM, optionally translates to a target language, and injects the result into your focused application via keyboard emulation.

**Key features:**

- **Real-time speech recognition** via Soniox realtime streaming ASR (stt-rt-v4)
- **OpenAI-compatible fallback** for HTTP-based ASR (e.g., OpenAI Realtime migration, local servers)
- **Text polish** via OpenRouter (GPT OSS 120B free) to clean disfluencies, fillers, grammar, and punctuation
- **Vocabulary biasing** with custom term hints (e.g., "Claude Code") sent to Soniox for better accuracy
- **Translation** via Ollama (hy-mt2 model) to English, Simplified Chinese, Traditional Chinese, or Korean
- **Three hotkey modes** on one key: Hold (push-to-talk), Tap (toggle), Double-tap (hands-free with silence auto-stop)
- **Liquid Glass UI** — borderless floating voice box with adjustable transparency, waveform visualization, and ChatWise-style settings window
- **Media control** — automatically pauses Spotify/Music during recording
- **Accessibility** — requires Microphone + Accessibility permissions; respects Reduce Transparency

## Requirements

- **macOS 26.0+** (Golden Gate compatible; tested with Xcode 26 Command Line Tools)
- **Xcode 26 Command Line Tools** (includes Swift 6 toolchain, language mode v5)
- **API Keys** (after first install):
  - `SONIOX_API_KEY` — for Soniox realtime ASR (get from [soniox.com](https://soniox.com))
  - `OPENROUTER_API_KEY` — for text polish via OpenRouter (free tier available)
  - Optional: `OLLAMA_API_KEY` if using non-local Ollama (default: `http://127.0.0.1:11434/v1`)

## Build

```bash
# One-shot build and install
make install

# Or step by step
make build          # Compile: swift build -c release
make run            # Launch app (for testing)
make clean          # Remove build artifacts
```

The Makefile assembles a proper `.app` bundle (VoiceInput.app) with:
- Binary at `Contents/MacOS/VoiceInput`
- Info.plist with `NSMicrophoneUsageDescription`, `NSAppleEventsUsageDescription` (for media pause)
- AppIcon.icns in `Contents/Resources`
- Ad-hoc code signature

## First Run

1. **Set up environment:**

   ```bash
   cd /path/to/voiceinput
   cp .env.local.example .env.local
   # Edit .env.local with your API keys (never commit this file)
   SONIOX_API_KEY=sk_...
   OPENROUTER_API_KEY=sk-or-v1-...
   ```

2. **Seed UserDefaults with keys:**

   ```bash
   bash scripts/seed-keys.sh
   ```

   This reads `.env.local` and populates `com.zhijie.VoiceInput` domain via `defaults write`.

3. **Grant permissions** (macOS will prompt first use, or grant manually):

   - **Microphone**: System Settings → Privacy & Security → Microphone → Enable VoiceInput
   - **Accessibility**: System Settings → Privacy & Security → Accessibility → Enable VoiceInput

4. **Configure & test:**

   - Launch VoiceInput (appears in menu bar as a mic icon)
   - Open Settings ("Settings…" in menu)
   - Go to **Providers** tab and click **Test** on Soniox to verify connectivity
   - Adjust **General** language hints, **Hotkey**, **Appearance** as desired

## Hotkey Modes

All three modes activate on a single key (default: Fn, customizable via Settings → Hotkey):

| Mode | Interaction | Behavior |
|------|---|---|
| **Hold** (≥200 ms) | Press and hold the hotkey | Push-to-talk: records while pressed; releases stops and injects. Forgiving 300 ms window—brief gaps don't end recording. |
| **Tap** (release <200 ms) | Quick tap | Toggle: first tap starts recording, second tap (or hotkey again) stops and injects. |
| **Hands-free** (double-tap within 350 ms) | Two quick taps | Starts recording; ends automatically on silence (2500 ms of no speech detected) or when you tap the hotkey again. Great for long monologues. |

Press **Esc** anywhere to cancel the current session (discards transcript, no injection).

## Providers Configuration

### ASR (Speech Recognition)

**Soniox Realtime** (primary, recommended):
- WebSocket realtime streaming at `wss://stt-rt.soniox.com/transcribe-websocket`
- Model: `stt-rt-v4` (current GA, supports 60+ languages, semantic endpoint detection)
- **Settings**: General → Language Hints (e.g., `zh,en` for mixed Chinese–English)
- **Providers** → Soniox: paste your API key, verify with Test button

**OpenAI-Compatible HTTP** (fallback):
- POST to `https://api.openai.com/v1/audio/transcriptions` or compatible endpoint
- Records audio as WAV, sends file on stop (no real-time transcript)
- **Limitation**: hands-free silence auto-stop is impossible (no interim results)—can only end via hotkey
- **Settings**: Providers → OpenAI-compatible ASR → set base URL, key, model name

### Text Polish

**OpenRouter + GPT OSS 120B:free**:
- Cleans disfluencies, fillers, repeats, false starts, punctuation, grammar
- Preserves meaning, tone, source language; keeps natural zh/en mix
- Temperature 0.3, max 2048 tokens
- Includes reasoning field (low effort) for deeper cleanup
- **Settings**: Providers → Polish → toggle Enable, set API key, model, Test

### Translation

**Ollama + hy-mt2-1.8b-translate**:
- Fast local neural machine translation (1.8B parameters)
- Targets: English, Simplified Chinese, Traditional Chinese, Korean
- Runs on `http://127.0.0.1:11434/v1` by default (local Ollama server)
- Can override base URL for remote Ollama
- Temperature 0.1 (deterministic)
- **Settings**: Providers → Translate → toggle Enable, pick target language, configure base URL if needed

## Vocabulary Correction

Custom vocabulary allows Soniox to recognize your preferred terms and polish to correct mishearings.

**Example:**
```
Term: Claude Code
Hints: cloud code, clot code
```

Soniox receives "Claude Code" in its context window for recognition biasing.
If it mishears "cloud code," the polish step uses the hint list to spot and correct it to "Claude Code."

**Settings:**
- Providers → Vocabulary tab
- Add entries: term (canonical form) + hints (comma-separated common mishearings)
- Delete with minus button; edit inline
- Entries persist to UserDefaults

**How it works:**
- Soniox context.terms: vocabulary canonical terms boost recognition accuracy
- Polish system prompt includes: `"If the transcript contains something like the left side, the speaker almost certainly meant the right side: - 'cloud code' → 'Claude Code'"` etc.
- Improves both ASR and post-hoc correction

## UI & Settings

### Overlay Panel (during recording)

- Floating Liquid Glass voice box (680 pt wide, center-screen X, positioned at 62% from bottom)
- **Transcript area** (top): final text + interim text with soft shimmer
- **Waveform** (center): real-time audio levels, ~72 rolling bars with gradient color
- **Bottom bar**:
  - Left: phase indicator dot (pulsing accent while listening, yellow finalizing, purple refining) + status label
  - Hands-free countdown pill (e.g., "2.5s") when active
  - Polish & Translate status chips (small gray pills, accent-tinted when enabled)
  - Right: Stop button + hotkey badge, Cancel button + Esc badge

### Settings Window (ChatWise style)

640×560 minimum, full-size content, hidden title bar, icon-tab strip:

1. **General**: App enable toggle, language hints field (ISO codes, e.g., `zh,en`)
2. **Hotkey**: Key picker (Fn, Right ⌘, Right ⌥, Right ⇧, Right ⌃, Custom), shortcut recorder, timing steppers (tap/hold threshold, double-press window, hold forgive, silence duration)
3. **Providers**: Master-detail source list (Soniox, OpenAI-compatible, Polish, Translate) with status dots and detail panes per provider
4. **Vocabulary**: Term + mishearings table, +/− buttons, explainer card
5. **Appearance**: Voice-box transparency slider (0% = clear glass, 100% = solid), vertical position slider, Preview button (shows sample transcription for 4 s)
6. **Permissions**: Microphone + Accessibility rows with status and grant buttons

Theme: ChatWise palette (blue accent #4E80EE light / #2464EB dark, warm stone sidebar, white content background). Light/dark mode automatic.

## Liquid Glass Transparency

Adjustable in Settings → Appearance (default 25%):

- **0%**: Pure Liquid Glass, highly transparent
- **25%**: Default—subtle frosted effect
- **100%**: Solid panel (opaque)

On macOS 27, your adjustment layers on top of the system Liquid Glass opacity slider.

Respects **Reduce Transparency** accessibility setting → forces opaque.

## Architecture

One Swift Package Module (VoiceInput), no inter-file imports needed:

- **App/**: AppDelegate, DictationController (orchestration), AppState
- **Core/**: AppSettings (UserDefaults-backed), VocabularyStore, Log (os.Logger)
- **Audio/**: AudioCapture (AVAudioEngine tap + format conversion)
- **ASR/**: Soniox realtime WebSocket, OpenAI-compatible HTTP transcription
- **Refine/**: Refiner (polish + translate chaining)
- **System/**: KeyMonitor (hotkey state machine), TextInjector, MediaController, PermissionStatus
- **UI/**: Theme (ChatWise palette), OverlayPanel (Liquid Glass voice box), SettingsWindow (SwiftUI)

## Troubleshooting

**Hotkey not working:**
- Check Settings → Hotkey → Test by pressing the configured key (status should change)
- Ensure Accessibility permission is granted (Settings → Permissions tab)
- Try resetting to Fn key (default)

**No audio capture:**
- Verify Microphone permission (Settings → Permissions → Grant)
- Check System Preferences → Security & Privacy → Microphone → VoiceInput enabled
- Test with `afplay` or built-in Audio MIDI Setup

**Soniox "auth" error:**
- Verify API key is correct (Settings → Providers → Soniox, Test button)
- Check `.env.local` and re-run `bash scripts/seed-keys.sh`

**Polish or Translate not working:**
- For Polish: verify OpenRouter API key, check OpenRouter account balance
- For Translate: ensure Ollama is running (`ollama serve`), pull model with `ollama pull hy-mt2-1.8b-translate:latest`
- Test buttons in Settings → Providers show errors inline

**Vocabulary not helping:**
- Verify entries are added in Settings → Vocabulary
- Check Soniox is the active ASR backend (Settings → Providers)
- Soniox context updates on next session (reconnect WebSocket)
- Try rebooting Soniox session if vocabulary was just added

## Development

Code compiles under Swift 6 (`swift build -c release`) with zero warnings, using language mode v5 to support pre-concurrency AppKit patterns. No third-party dependencies—AppKit, SwiftUI, Foundation, AVFoundation, Carbon (TIS) only.

Follows the contract in SPEC.md (public interface compliance). All main-thread mutations in AppState, callbacks on main thread, generation counters for session invalidation, graceful fallback on LLM failures.

## License

Proprietary—see LICENSE file.
