import SwiftUI

/// ChatWise-style master-detail provider configuration. A narrow source list
/// names each backend with a configured/unconfigured status dot; the detail
/// pane shows only that provider's fields.
struct ProvidersTab: View {
    let refiner: Refiner

    @EnvironmentObject private var settings: AppSettings

    @State private var selection: ProviderItem = .sonioxRealtime
    @State private var polishOutcome: TestOutcome = .idle
    @State private var translateOutcome: TestOutcome = .idle

    enum ProviderItem: String, CaseIterable, Identifiable {
        case sonioxRealtime
        case httpASR
        case polish
        case translate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sonioxRealtime: return "Soniox Realtime"
            case .httpASR:        return "OpenAI-compatible ASR"
            case .polish:         return "Polish · OpenRouter"
            case .translate:      return "Translate · Ollama"
            }
        }

        var symbol: String {
            switch self {
            case .sonioxRealtime: return "waveform"
            case .httpASR:        return "network"
            case .polish:         return "sparkles"
            case .translate:      return "globe"
            }
        }
    }

    /// User-adjustable source-list width, persisted across launches.
    @AppStorage("providersSidebarWidth") private var sidebarWidth: Double = 170

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sourceList
            SplitDragHandle(width: $sidebarWidth, range: 140...320)
            detail
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Source list

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ProviderItem.allCases) { item in
                SourceListRow(
                    symbol: item.symbol,
                    title: item.title,
                    configured: isConfigured(item),
                    isSelected: selection == item
                ) {
                    selection = item
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: max(140, sidebarWidth), alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.sidebarBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private func isConfigured(_ item: ProviderItem) -> Bool {
        switch item {
        case .sonioxRealtime:
            return !settings.sonioxAPIKey.trimmed.isEmpty
        case .httpASR:
            return !settings.httpASRBaseURL.trimmed.isEmpty && !settings.httpASRModel.trimmed.isEmpty
        case .polish:
            return !settings.polishBaseURL.trimmed.isEmpty && !settings.polishModel.trimmed.isEmpty
        case .translate:
            return !settings.translateBaseURL.trimmed.isEmpty && !settings.translateModel.trimmed.isEmpty
        }
    }

    // MARK: Detail panes

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .sonioxRealtime: sonioxPane
        case .httpASR:        httpPane
        case .polish:         polishPane
        case .translate:      translatePane
        }
    }

    // Shared "Active backend" picker that sits atop both ASR pages.
    private var activeBackendPicker: some View {
        InlineRow(
            title: "Active backend",
            help: "Which engine handles speech recognition for this app."
        ) {
            ThemedPicker(selection: $settings.asrBackend, width: 200) {
                ForEach(ASRBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
        }
    }

    private var sonioxPane: some View {
        Card {
            CardHeading(
                title: "Soniox Realtime",
                subtitle: "Streaming WebSocket ASR with live partial results and endpoint detection."
            )
            activeBackendPicker
            Hairline()
            FieldRow(
                title: "API key",
                help: "Soniox API key. Stored in your local preferences."
            ) {
                SecureFieldRow(placeholder: "soniox-…", text: $settings.sonioxAPIKey)
            }
            FieldRow(
                title: "Model",
                help: "Realtime model identifier."
            ) {
                ModelPickerField(
                    placeholder: "stt-rt-v4",
                    model: $settings.sonioxModel,
                    kind: .sonioxRealtime
                )
            }
        }
    }

    private var httpPane: some View {
        Card {
            CardHeading(
                title: "OpenAI-compatible ASR",
                subtitle: "Records locally, then uploads one WAV to /audio/transcriptions. No live partials."
            )
            activeBackendPicker
            Hairline()
            FieldRow(
                title: "Base URL",
                help: "e.g. https://api.openai.com/v1 or a compatible server."
            ) {
                FilledTextField(placeholder: "https://api.openai.com/v1", text: $settings.httpASRBaseURL, monospaced: true)
            }
            FieldRow(
                title: "API key",
                help: "Bearer token (optional for some local servers)."
            ) {
                SecureFieldRow(placeholder: "sk-…", text: $settings.httpASRAPIKey)
            }
            FieldRow(
                title: "Model",
                help: "Transcription model identifier."
            ) {
                ModelPickerField(
                    placeholder: "gpt-4o-mini-transcribe",
                    model: $settings.httpASRModel,
                    kind: .transcription,
                    baseURL: { settings.httpASRBaseURL },
                    apiKey: { settings.httpASRAPIKey }
                )
            }
        }
    }

    private var polishPane: some View {
        Card {
            CardHeading(
                title: "Polish · OpenRouter",
                subtitle: "Cleans disfluencies, fillers, and punctuation while preserving meaning and language."
            )
            InlineRow(
                title: "Enable polish",
                help: "Run a cleanup pass on every transcript."
            ) {
                BlueToggle(isOn: $settings.polishEnabled)
            }
            Hairline()
            FieldRow(
                title: "Base URL",
                help: "OpenRouter or any OpenAI-compatible chat-completions endpoint."
            ) {
                FilledTextField(placeholder: "https://openrouter.ai/api/v1", text: $settings.polishBaseURL, monospaced: true)
            }
            FieldRow(
                title: "API key",
                help: "Bearer token for the polish endpoint."
            ) {
                SecureFieldRow(placeholder: "sk-or-v1-…", text: $settings.polishAPIKey)
            }
            FieldRow(
                title: "Model",
                help: "Chat model identifier."
            ) {
                ModelPickerField(
                    placeholder: "openai/gpt-oss-120b:free",
                    model: $settings.polishModel,
                    kind: .chat,
                    baseURL: { settings.polishBaseURL },
                    apiKey: { settings.polishAPIKey }
                )
            }
            InlineRow(
                title: "Reasoning effort",
                help: "For reasoning models (gpt-oss…). OpenRouter gets the nested reasoning object; OpenAI/Cerebras-style endpoints get reasoning_effort. Off sends neither."
            ) {
                Picker("", selection: $settings.polishReasoningEffort) {
                    Text("Off").tag("off")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            Hairline()
            TestButton(title: "Test Polish", outcome: polishOutcome) {
                runPolishTest()
            }
        }
    }

    private var translatePane: some View {
        Card {
            CardHeading(
                title: "Translate · Ollama",
                subtitle: "Optional final translation step into your target language."
            )
            InlineRow(
                title: "Enable translate",
                help: "Translate the (polished) transcript before injecting."
            ) {
                BlueToggle(isOn: $settings.translateEnabled)
            }
            Hairline()
            InlineRow(
                title: "Target language",
                help: "Language the transcript is translated into."
            ) {
                ThemedPicker(selection: $settings.translateTarget, width: 200) {
                    ForEach(TranslateTarget.allCases, id: \.self) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .disabled(!settings.translateEnabled)
            }
            FieldRow(
                title: "Base URL",
                help: "Ollama or any OpenAI-compatible chat-completions endpoint."
            ) {
                FilledTextField(placeholder: "http://127.0.0.1:11434/v1", text: $settings.translateBaseURL, monospaced: true)
            }
            FieldRow(
                title: "API key",
                help: "Bearer token (optional for local Ollama)."
            ) {
                SecureFieldRow(placeholder: "(optional)", text: $settings.translateAPIKey)
            }
            FieldRow(
                title: "Model",
                help: "Translation model identifier."
            ) {
                ModelPickerField(
                    placeholder: "hy-mt2-1.8b-translate:latest",
                    model: $settings.translateModel,
                    kind: .chat,
                    baseURL: { settings.translateBaseURL },
                    apiKey: { settings.translateAPIKey }
                )
            }
            Hairline()
            TestButton(title: "Test Translate", outcome: translateOutcome) {
                runTranslateTest()
            }
        }
    }

    // MARK: Tests

    private func runPolishTest() {
        polishOutcome = .running
        refiner.testPolish { result in
            switch result {
            case .success(let text):
                polishOutcome = .success(text)
            case .failure(let error):
                polishOutcome = .failure(error.localizedDescription)
            }
        }
    }

    private func runTranslateTest() {
        translateOutcome = .running
        refiner.testTranslate { result in
            switch result {
            case .success(let text):
                translateOutcome = .success(text)
            case .failure(let error):
                translateOutcome = .failure(error.localizedDescription)
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
