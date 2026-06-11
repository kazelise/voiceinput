import SwiftUI

/// Appearance settings: the voice box's transparency and vertical screen
/// position, with a live miniature preview and a button to flash the real
/// overlay on screen.
struct AppearanceTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            previewCard
            controlsCard
        }
    }

    // MARK: Live preview

    private var previewCard: some View {
        Card {
            CardHeading(
                title: "Voice box",
                subtitle: "Preview reflects your transparency setting live."
            )
            MiniVoiceBoxPreview(opacity: settings.voiceBoxOpacity)
                .frame(height: 96)
                .frame(maxWidth: .infinity)

            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("VoiceInputPreviewOverlay"),
                    object: nil
                )
            } label: {
                Label("Preview voice box", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(Theme.accent)
        }
    }

    // MARK: Sliders

    private var controlsCard: some View {
        Card {
            FieldRow(
                title: "Transparency",
                help: "0% = clear liquid glass, 100% = solid."
            ) {
                HStack(spacing: 12) {
                    Slider(value: $settings.voiceBoxOpacity, in: 0...1)
                        .tint(Theme.accent)
                    Text("\(percent(settings.voiceBoxOpacity))%")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Hairline()

            FieldRow(
                title: "Vertical position",
                help: "Distance from the bottom of the screen. Dragging the box anywhere overrides this until you reset."
            ) {
                HStack(spacing: 12) {
                    Slider(value: $settings.voiceBoxVerticalPosition, in: 0.30...0.90)
                        .tint(Theme.accent)
                    Text("\(percent(settings.voiceBoxVerticalPosition))%")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 48, alignment: .trailing)
                    Button("Reset position") {
                        settings.voiceBoxOriginX = -1
                        settings.voiceBoxOriginY = -1
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(settings.voiceBoxOriginX < 0)
                }
            }
        }
    }

    private func percent(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }
}

/// A small static rendition of the glass box that re-paints as the opacity
/// slider moves — a calm, immediate visual of the chosen transparency.
private struct MiniVoiceBoxPreview: View {
    let opacity: Double

    var body: some View {
        ZStack {
            // A faux "wallpaper" so transparency reads at a glance.
            LinearGradient(
                colors: [Theme.accent.opacity(0.35), Color.purple.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape
                .fill(Color(nsColor: .windowBackgroundColor).opacity(max(0.06, opacity)))
                .overlay(
                    shape.strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .overlay(content)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listening…")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            HStack(spacing: 3) {
                ForEach(0..<22, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 2.5, height: barHeight(i))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let phase = Double(index) / 3.0
        return 6 + CGFloat(abs(sin(phase)) * 18)
    }
}
