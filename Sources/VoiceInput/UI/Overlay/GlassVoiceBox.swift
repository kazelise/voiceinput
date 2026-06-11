import SwiftUI

/// Holds the "Stop" badge text — the user's current hotkey display name.
///
/// Owned by `OverlayPanel` and mutated by `OverlayPanel.updateHotkeyLabel(_:)`.
/// Observed by the box so the badge re-renders live without rebuilding the
/// hosting view.
final class HotkeyLabelModel: ObservableObject {
    @Published var label: String

    init(label: String = "Fn") {
        self.label = label
    }
}

/// The Liquid Glass dictation box — the visual centerpiece of the app.
///
/// A single 680-pt rounded card floating over the desktop. It is built from
/// system Liquid Glass (`glassEffect`) plus a user-adjustable scrim (Approach B
/// from `docs/research/liquid-glass.md`): the glass provides refraction and
/// adaptive blur, and a `windowBackgroundColor` fill on top, keyed to
/// `settings.voiceBoxOpacity`, lets the user dial from "pure clear glass" to
/// "solid panel". A kube.io-inspired specular rim (an angular-gradient stroke
/// brightest near the 60° light direction, plus an inner hairline) gives the
/// edge its polished, luminous bevel.
///
/// All visible state derives reactively from `AppState` and `AppSettings`;
/// there are no imperative update methods.
struct GlassVoiceBox: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: AppSettings

    /// The Stop badge text (the user's hotkey display name) supplied by the
    /// AppDelegate via `OverlayPanel.updateHotkeyLabel`. Held by the panel and
    /// observed here so the badge updates live.
    @ObservedObject var hotkeyLabel: HotkeyLabelModel

    var onStop: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let boxWidth: CGFloat = 680
    private let cornerRadius: CGFloat = 28

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var isError: Bool {
        if case .error = state.phase { return true }
        return false
    }

    // The box uses exactly ONE Liquid Glass surface: the background. Putting a
    // second glass level (e.g. glass buttons) above the content inside a shared
    // GlassEffectContainer makes the system composite all glass in one pass
    // ABOVE the sandwiched content, fogging the transcript/waveform/chips.
    var body: some View {
        Group {
            if settings.voiceBoxCompact {
                compactBody
            } else {
                expandedBody
            }
        }
        .animation(.spring(duration: 0.35), value: settings.voiceBoxCompact)
        .animation(.spring(duration: 0.35), value: state.phase)
        .animation(.spring(duration: 0.35), value: state.silenceCountdown != nil)
        .animation(.spring(duration: 0.35), value: settings.polishEnabled)
        .animation(.spring(duration: 0.35), value: settings.translateEnabled)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            transcriptArea
            WaveformView(state: state)
                .padding(.horizontal, 2)
            bottomBar
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: boxWidth, alignment: .leading)
        .background(glassBackground(shape))
        .overlay(specularRim(shape))
        .overlay(errorRim(shape))
        .clipShape(shape)
        .modifier(BoxChrome())
    }

    // MARK: - Compact capsule

    /// The minimized form: phase dot + mini waveform + stop + expand, in a
    /// single glass capsule. The hotkey and Esc keep working as usual.
    private var compactBody: some View {
        let capsule = Capsule(style: .continuous)
        return HStack(spacing: 12) {
            PhaseDot(phase: state.phase)
            WaveformView(state: state, barCount: 26, height: 20)
            if let countdown = state.silenceCountdown {
                Text(String(format: "%.1f", max(0, countdown)))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.yellow.opacity(0.95))
            }
            IconChipButton(systemName: "stop.fill", help: "Stop", action: onStop)
            IconChipButton(
                systemName: "arrow.up.left.and.arrow.down.right",
                help: "Expand"
            ) {
                settings.voiceBoxCompact = false
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(glassBackground(capsule))
        .overlay(specularRim(capsule))
        .overlay(errorRim(capsule))
        .clipShape(capsule)
        .modifier(BoxChrome())
    }

    // MARK: - Glass + scrim background (Approach B)

    @ViewBuilder
    private func glassBackground<S: InsettableShape>(_ shape: S) -> some View {
        let opacity = settings.voiceBoxOpacity
        ZStack {
            // System Liquid Glass base — dropped when the user wants a solid
            // panel (opacity ≥ 0.99) or when Reduce Transparency is on.
            if !reduceTransparency && opacity < 0.99 {
                Color.clear.glassEffect(.regular, in: shape)
            }
            // The adjustable scrim. windowBackgroundColor adapts to light/dark
            // for free. Forced fully opaque under Reduce Transparency.
            shape.fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(reduceTransparency ? 1 : opacity)
            )
            // Error phase tints the scrim red behind the content (the border
            // flash is layered separately in `errorRim`).
            if isError {
                shape.fill(Color.red.opacity(0.10))
            }
        }
    }

    // MARK: - kube.io specular rim

    /// A 1.5 pt angular-gradient stroke, brightest near the 60° light direction,
    /// plus a hairline inner stroke. Reads as a catch-light on a bevelled edge —
    /// an accent, never a hard outline.
    private func specularRim<S: InsettableShape>(_ shape: S) -> some View {
        ZStack {
            shape
                .strokeBorder(specularGradient, lineWidth: 1.5)
            shape
                .inset(by: 1.5)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// Angular sweep peaking around the upper-left light source (~60° measured
    /// from the +x axis, i.e. top-leading), with a quadratic-ish falloff to a
    /// dim base everywhere else.
    private var specularGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: .white.opacity(0.05), location: 0.00),
                Gradient.Stop(color: .white.opacity(0.50), location: 0.16), // ~60° catch-light (SPEC peak)
                Gradient.Stop(color: .white.opacity(0.12), location: 0.34),
                Gradient.Stop(color: .white.opacity(0.05), location: 0.55),
                Gradient.Stop(color: .white.opacity(0.22), location: 0.70), // soft opposite catch
                Gradient.Stop(color: .white.opacity(0.05), location: 1.00),
            ]),
            center: .center,
            angle: .degrees(-90) // rotate so 0 fraction starts near top
        )
    }

    /// The error-phase border flash. The red scrim itself lives in
    /// `glassBackground` so it sits behind the error text.
    @ViewBuilder
    private func errorRim<S: InsettableShape>(_ shape: S) -> some View {
        if isError {
            shape
                .strokeBorder(Color.red.opacity(0.7), lineWidth: 1.5)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - Transcript area

    private var transcriptArea: some View {
        Group {
            if isError {
                Text(errorMessage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.92))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state.transcript.isEmpty {
                Text(placeholder)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .lineLimit(1)
            } else {
                scrollingTranscript
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    /// The live transcript in a pinned-to-tail scroll view: as new words stream
    /// in past three lines, the view follows the freshest text automatically.
    /// The user can still flick upward to re-read; the next update re-pins.
    private var scrollingTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                transcriptText
                    .font(.system(size: 17, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 1)
                    .id("transcriptTail")
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .frame(maxHeight: 70) // ~3 lines at 17 pt; shorter text stays snug
            .onChange(of: state.transcript) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("transcriptTail", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("transcriptTail", anchor: .bottom)
            }
        }
    }

    /// Final text in primary colour, interim text in secondary at 60 % with a
    /// soft fade so freshly-arriving words shimmer in rather than pop. Built as
    /// a two-run `AttributedString` so the styling is one `Text` (avoids the
    /// deprecated `Text + Text` concatenation).
    private var transcriptText: Text {
        var attributed = AttributedString(state.transcript.finalText)
        attributed.foregroundColor = Theme.textPrimary

        var interim = AttributedString(state.transcript.interimText)
        interim.foregroundColor = Theme.textSecondary.opacity(0.6)

        // A hair of leading space already lives in the interim text from the
        // ASR; concatenate verbatim so spacing matches the source.
        attributed.append(interim)
        return Text(attributed)
    }

    private var errorMessage: String {
        if case let .error(message) = state.phase { return message }
        return ""
    }

    /// Placeholder copy keyed to phase + the user's primary language hint.
    private var placeholder: String {
        let chinese = prefersChinese
        switch state.phase {
        case .connecting:
            return chinese ? "连接中…" : "Connecting…"
        default:
            return chinese ? "聆听中…" : "Listening…"
        }
    }

    private var prefersChinese: Bool {
        settings.languageHintsArray.first?.hasPrefix("zh") ?? false
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            phaseIndicator
            if let countdown = state.silenceCountdown {
                countdownPill(countdown)
            }
            chips
            Spacer(minLength: 12)
            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Phase dot + label, derived solely from `state.phase`.
    private var phaseIndicator: some View {
        HStack(spacing: 8) {
            PhaseDot(phase: state.phase)
            Text(phaseLabel)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
        .fixedSize()
    }

    private var phaseLabel: String {
        switch state.phase {
        case .connecting: return "Connecting…"
        case .listening:  return "Listening"
        case .finalizing: return "Finalizing"
        case .refining:   return "Refining"
        case .injecting:  return "Inserting"
        case .idle:       return "Ready"
        case .error:      return "Error"
        }
    }

    // Hands-free silence countdown, e.g. "2.5s".
    private func countdownPill(_ remaining: Double) -> some View {
        Text(String(format: "%.1fs", max(0, remaining)))
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.yellow.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.yellow.opacity(0.14))
            )
            .overlay(
                Capsule().strokeBorder(Color.yellow.opacity(0.4), lineWidth: 0.75)
            )
            .transition(.scale.combined(with: .opacity))
    }

    // Tapping a chip toggles its feature for this and future sessions.
    private var chips: some View {
        HStack(spacing: 6) {
            Button { settings.polishEnabled.toggle() } label: {
                FeatureChip(title: "Polish", active: settings.polishEnabled)
            }
            .buttonStyle(.plain)

            Button { settings.translateEnabled.toggle() } label: {
                FeatureChip(
                    title: "Translate",
                    trailing: settings.translateTarget.shortLabel,
                    active: settings.translateEnabled
                )
            }
            .buttonStyle(.plain)
        }
    }

    // Right cluster: minimize + Stop / Cancel capsules. Deliberately NOT glass —
    // a second glass level above the content would fog everything beneath it
    // (see body).
    private var actionButtons: some View {
        HStack(spacing: 8) {
            IconChipButton(
                systemName: "arrow.down.right.and.arrow.up.left",
                help: "Minimize to capsule"
            ) {
                settings.voiceBoxCompact = true
            }

            GlassActionButton(
                title: "Stop",
                badge: hotkeyLabel.label,
                action: onStop
            )

            GlassActionButton(
                title: "Cancel",
                badge: "esc",
                action: onCancel
            )
        }
        .fixedSize()
    }
}

// MARK: - Shared box chrome

/// Shadow, drag-to-move, and shadow-breathing padding shared by the expanded
/// box and the compact capsule. A whisper of a shadow — anything heavier makes
/// the apps behind the glass look murky.
private struct BoxChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 5)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            // Drag anywhere on the box to move it; buttons/chips still win
            // clicks because child gestures take precedence. OverlayPanel
            // persists the dragged-to origin via NSWindow.didMoveNotification.
            .gesture(WindowDragGesture())
            .padding(40) // breathing room for the shadow so the panel doesn't clip it
    }
}

// MARK: - Icon chip button

/// A small circular icon control (minimize/expand/stop) matching the chip
/// idiom: quiet by default, brightens on hover.
private struct IconChipButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(
                    hovering ? Theme.textPrimary : Theme.textSecondary.opacity(0.9)
                )
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(
                        Color.primary.opacity(
                            (colorScheme == .dark ? 0.10 : 0.06) + (hovering ? 0.05 : 0)
                        )
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
    }
}

// MARK: - Phase dot

/// The 8-pt status dot. Accent and pulsing while listening; yellow while
/// finalizing; purple while refining; static otherwise.
private struct PhaseDot: View {
    let phase: DictationPhase

    @State private var pulse = false

    private var color: Color {
        switch phase {
        case .listening:  return Theme.accent
        case .finalizing: return .yellow
        case .refining:   return .purple
        case .injecting:  return Theme.accent
        case .connecting: return Theme.accent.opacity(0.7)
        case .error:      return .red
        case .idle:       return .secondary
        }
    }

    private var isPulsing: Bool {
        if case .listening = phase { return true }
        return false
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(pulse ? 2.1 : 1)
                    .opacity(pulse ? 0 : 0.6)
            )
            .animation(
                isPulsing
                    ? .easeOut(duration: 1.1).repeatForever(autoreverses: false)
                    : .default,
                value: pulse
            )
            .onAppear { if isPulsing { pulse = true } }
            .onChange(of: isPulsing) { _, newValue in
                pulse = newValue
            }
    }
}

// MARK: - Feature chip

/// A small gray pill that tints toward the accent when its feature is enabled.
/// Optionally carries a trailing label (the translate target, e.g. "EN").
private struct FeatureChip: View {
    let title: String
    var trailing: String? = nil
    let active: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(active ? Theme.accent : Theme.textSecondary.opacity(0.85))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(
                active
                    ? Theme.accent.opacity(0.16)
                    : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                active ? Theme.accent.opacity(0.4) : Color.clear,
                lineWidth: 0.75
            )
        )
        .fixedSize()
    }
}

// MARK: - Glass action button

/// A tiny capsule button: title + a keycap-style badge. Renders as a crisp
/// translucent capsule sitting ON the panel's single glass surface — it must
/// not carry its own `glassEffect` (nested glass above content fogs the box).
private struct GlassActionButton: View {
    let title: String
    let badge: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(hovering ? 1 : 0.9))
                Text(badge)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    Color.primary.opacity(
                        (colorScheme == .dark ? 0.10 : 0.06) + (hovering ? 0.05 : 0)
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
