import SwiftUI

/// Two-column Live Captions glass card: original speech on the left,
/// Soniox one-way translation on the right. Same Liquid Glass language as the
/// voice box — single glass surface + user-opacity scrim, specular rim, drag
/// grabber, tail-pinned fading transcript columns.
struct ListenView: View {
    @ObservedObject var state: ListenState
    @ObservedObject var settings: AppSettings

    var onClose: () -> Void
    var onClear: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            columns
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(glassBackground)
        .overlay(specularRim)
        .clipShape(shape)
        .overlay(alignment: .top) { ListenDragGrabber().padding(.top, 6) }
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 5)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .gesture(WindowDragGesture())
        .padding(40)
        .animation(.spring(duration: 0.3), value: state.errorMessage)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ListenPulseDot(active: state.active, connecting: state.connecting)
            Text("Live Captions")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))

            sourceMenu

            if let error = state.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            MiniWaveform(level: state.audioLevel)
                .frame(width: 60, height: 16)

            ListenIconButton(systemName: "trash", help: "Clear transcripts", action: onClear)
            ListenIconButton(systemName: "xmark", help: "Close (Fn+Space)", action: onClose)
        }
    }

    private var sourceMenu: some View {
        Menu {
            Button {
                settings.listenSource = "system"
            } label: {
                label("System audio", checked: settings.listenSource == "system")
            }
            Button {
                settings.listenSource = "mic"
            } label: {
                label("Microphone", checked: settings.listenSource == "mic")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: settings.listenSource == "mic" ? "mic" : "speaker.wave.2")
                    .font(.system(size: 10, weight: .medium))
                Text(settings.listenSource == "mic" ? "Microphone" : "System audio")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Columns

    private var columns: some View {
        HStack(alignment: .top, spacing: 16) {
            column(
                titleView: AnyView(
                    Text("Original")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                ),
                snapshot: state.original,
                placeholder: state.connecting ? "Connecting…" : "Listening…",
                id: "original"
            )

            Rectangle()
                .fill(Theme.hairline.opacity(0.6))
                .frame(width: 1)
                .padding(.vertical, 2)

            column(
                titleView: AnyView(targetMenu),
                snapshot: state.translation,
                placeholder: "Translation appears here…",
                id: "translation"
            )
        }
    }

    private var targetMenu: some View {
        Menu {
            ForEach(ListenLanguages.all, id: \.code) { language in
                Button {
                    settings.listenTargetLanguage = language.code
                } label: {
                    label(language.name, checked: settings.listenTargetLanguage == language.code)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 9, weight: .medium))
                Text(ListenLanguages.name(for: settings.listenTargetLanguage))
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent.opacity(0.14)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Translation target — changing restarts the stream, keeping the text so far")
    }

    private func column(titleView: AnyView, snapshot: TranscriptSnapshot,
                        placeholder: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleView
            if snapshot.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                tailPinnedScroll(snapshot: snapshot, id: id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tailPinnedScroll(snapshot: TranscriptSnapshot, id: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                columnText(snapshot)
                    .font(.system(size: 15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 1)
                    .id("tail-\(id)")
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .clipped()
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14)
                    Color.black
                }
            )
            .onChange(of: snapshot) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("tail-\(id)", anchor: .bottom)
                }
            }
            .onAppear { proxy.scrollTo("tail-\(id)", anchor: .bottom) }
        }
    }

    private func columnText(_ snapshot: TranscriptSnapshot) -> Text {
        var attributed = AttributedString(snapshot.finalText)
        attributed.foregroundColor = Theme.textPrimary
        var interim = AttributedString(snapshot.interimText)
        interim.foregroundColor = Theme.textSecondary.opacity(0.6)
        attributed.append(interim)
        return Text(attributed)
    }

    // MARK: - Glass (same single-surface recipe as the voice box)

    @ViewBuilder
    private var glassBackground: some View {
        let opacity = settings.voiceBoxOpacity
        ZStack {
            if !reduceTransparency && opacity < 0.99 {
                Color.clear.glassEffect(.regular, in: shape)
            }
            shape.fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(reduceTransparency ? 1 : opacity)
            )
        }
    }

    private var specularRim: some View {
        ZStack {
            shape.strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.05), location: 0.00),
                        .init(color: .white.opacity(0.50), location: 0.16),
                        .init(color: .white.opacity(0.12), location: 0.34),
                        .init(color: .white.opacity(0.05), location: 0.55),
                        .init(color: .white.opacity(0.22), location: 0.70),
                        .init(color: .white.opacity(0.05), location: 1.00),
                    ]),
                    center: .center,
                    angle: .degrees(-90)
                ),
                lineWidth: 1.5
            )
            shape.inset(by: 1.5)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private func label(_ title: String, checked: Bool) -> some View {
        HStack {
            if checked { Image(systemName: "checkmark") }
            Text(title)
        }
    }
}

// MARK: - Small components

private struct ListenPulseDot: View {
    let active: Bool
    let connecting: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(connecting ? Theme.accent.opacity(0.6) : (active ? Theme.accent : .secondary))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Theme.accent, lineWidth: 2)
                    .scaleEffect(pulse ? 2.1 : 1)
                    .opacity(pulse ? 0 : 0.6)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

/// Tiny five-bar level meter for the header (full waveform lives in the box).
private struct MiniWaveform: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<9, id: \.self) { index in
                Capsule()
                    .fill(Theme.accent.opacity(0.85))
                    .frame(width: 2.5, height: barHeight(index))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let envelope = sin(Double(index + 1) / 10.0 * .pi)   // taller in the middle
        return 3 + CGFloat(Double(level) * envelope) * 13
    }
}

private struct ListenIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary.opacity(0.9))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
    }
}

private struct ListenDragGrabber: View {
    @State private var hovering = false

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(hovering ? 0.32 : 0.15))
            .frame(width: 42, height: 4.5)
            .frame(width: 150, height: 20)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help("Drag to move")
    }
}
