# Gemini Live API — Live Captions translation backend

Researched June 2026. The translate model is PUBLIC PREVIEW; re-verify the model id and `translationConfig` shape against ai.google.dev before relying on it.

## Model
- Translate model id: `gemini-3.5-live-translate-preview` → in setup, `models/gemini-3.5-live-translate-preview`.
- Speech-to-SPEECH translator: forces `responseModalities: ["AUDIO"]`. The text we want comes as transcription sidecars (input = original, output = translation). Synthesized audio is discarded for a captions UI ($21/1M audio-output tokens — real cost).
- Source language auto-detected (no source field). Target via `translationConfig.targetLanguageCode` (BCP-47; Simplified Chinese = `zh-CN`).
- Cheaper text-only alternative: a general live model (e.g. `gemini-2.5-flash-native-audio`) with `responseModalities:["TEXT"]` + `inputAudioTranscription:{}` + a translate `systemInstruction`; model text output = translation. Our `GeminiListenSession` auto-picks this path when the model id lacks "translate".

## Endpoint
```
wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=API_KEY
```
AI Studio key works directly. Send exactly one `setup` first, wait for `setupComplete`, then stream.

## Setup (translate model)
```json
{"setup":{
  "model":"models/gemini-3.5-live-translate-preview",
  "generationConfig":{
    "responseModalities":["AUDIO"],
    "inputAudioTranscription":{},
    "outputAudioTranscription":{},
    "translationConfig":{"targetLanguageCode":"zh-CN","echoTargetLanguage":false}
  },
  "contextWindowCompression":{"slidingWindow":{}},
  "sessionResumption":{}
}}
```
`contextWindowCompression.slidingWindow` lifts the 15-min audio cap. `sessionResumption.handle` reconnects seamlessly.

## Audio in (matches our 16k mono s16le AudioCapture — no resample)
```json
{"realtimeInput":{"audio":{"data":"<base64 PCM>","mimeType":"audio/pcm;rate=16000"}}}
```
~100 ms chunks. Close with `{"realtimeInput":{"audioStreamEnd":true}}`.

## Server messages
- `setupComplete` → gate audio on this.
- `serverContent.inputTranscription.text` (+ `.languageCode`) → ORIGINAL (left column).
- `serverContent.outputTranscription.text` → TRANSLATION (right column) for translate model.
- `serverContent.modelTurn.parts[].text` → translation for the TEXT-model path; `.inlineData` (24kHz PCM) = translated audio, ignored.
- `serverContent.turnComplete` → turn boundary. Transcription streams incrementally (concatenate deltas).
- `goAway` (~60s warning, has `timeLeft`) → reconnect with resumption handle.
- `sessionResumptionUpdate.newHandle` when `resumable==true` (valid 2h) → keep latest.

## Limits
Token-based ($21/1M audio in & out, $3.50/1M text). ~10-min socket life, 15-min audio session (extend via compression). Preview models usually need billing enabled. Rate limits per project.

Sources: ai.google.dev/gemini-api/docs/live-api/live-translate, /api/live, /docs/models/gemini-3.5-live-translate-preview, blog.google Gemini 3.5 Live Translate.
