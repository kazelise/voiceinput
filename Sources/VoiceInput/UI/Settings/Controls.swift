import AppKit
import SwiftUI

// MARK: - Card

/// A ChatWise content card: `Theme.contentBackground`, 10 pt radius, hairline
/// border. Hairlines and whitespace, never heavy boxes.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.contentBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

/// A 1 pt hairline rule in the theme color — used between rows instead of a
/// chunky `Divider`.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

// MARK: - Field row scaffolding

/// The canonical form row: a 13 pt semibold label, 12 pt secondary helper text
/// directly under it, then the control. This is the single idiom every tab
/// composes from.
struct FieldRow<Control: View>: View {
    let title: String
    var help: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let help {
                    Text(help)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row whose control sits to the right of the label (toggles, pickers,
/// steppers) — label + helper on the left, control trailing-aligned.
struct InlineRow<Control: View>: View {
    let title: String
    var help: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let help {
                    Text(help)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Text fields

/// Filled, rounded text field: `Theme.fieldFill`, radius 8, hairline border —
/// the System-Settings field look, not the default bezel.
struct FilledTextField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced
                  ? .system(size: 13, design: .monospaced)
                  : .system(size: 13))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(fieldShape.fill(Theme.fieldFill))
            .overlay(fieldShape.strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

/// SecureField for API keys with a show/hide eye toggle. Matches the filled
/// field look so the row reads consistently.
struct SecureFieldRow: View {
    let placeholder: String
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(revealed ? "Hide" : "Show")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(fieldShape.fill(Theme.fieldFill))
        .overlay(fieldShape.strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

// MARK: - Toggle

/// Blue, right-aligned switch matching ChatWise toggles.
struct BlueToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .controlSize(.regular)
    }
}

// MARK: - Pickers

/// A popup-button picker styled with the accent tint and a fixed width so rows
/// align cleanly.
struct ThemedPicker<SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: SelectionValue
    var width: CGFloat = 220
    @ViewBuilder var content: Content

    var body: some View {
        Picker("", selection: $selection) {
            content
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Theme.accent)
        .frame(width: width)
    }
}

// MARK: - Test button + inline result

/// Result of a "Test" round-trip rendered inline next to the button.
enum TestOutcome: Equatable {
    case idle
    case running
    case success(String)
    case failure(String)
}

/// A `.bordered` Test button with an inline ✓ / ✗ result. Used by the Polish
/// and Translate detail panes.
struct TestButton: View {
    let title: String
    let outcome: TestOutcome
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: action) {
                HStack(spacing: 5) {
                    if outcome == .running {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(title)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(Theme.accent)
            .disabled(outcome == .running)

            resultView
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var resultView: some View {
        switch outcome {
        case .idle, .running:
            EmptyView()
        case .success(let text):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                Text(text)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .font(.system(size: 12))
        case .failure(let message):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.red)
                Text(message)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .font(.system(size: 12))
        }
    }
}

// MARK: - Status dot

/// Small filled dot: green when a provider is configured, gray otherwise.
struct StatusDot: View {
    let configured: Bool

    var body: some View {
        Circle()
            .fill(configured ? Color.green : Theme.textSecondary.opacity(0.4))
            .frame(width: 7, height: 7)
    }
}

// MARK: - ChatWise +/- list controls

/// The +/- bordered button strip anchored at a list's bottom-left, ChatWise
/// style. Used by the Vocabulary table.
struct ListControlBar: View {
    let canRemove: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            controlButton(system: "plus", action: onAdd)
                .help("Add term")
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1, height: 14)
            controlButton(system: "minus", action: onRemove)
                .disabled(!canRemove)
                .help("Remove selected term")
            Spacer()
        }
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .fixedSize()
    }

    private func controlButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Master-detail source-list row

/// A row in the Providers source list: optional SF Symbol, title, status dot,
/// selectable with an accent-tinted highlight.
struct SourceListRow: View {
    let symbol: String
    let title: String
    let configured: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 6)
                StatusDot(configured: configured)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.pill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section heading inside a card

/// A lightweight in-card heading: weight-and-spacing hierarchy, no uppercase.
struct CardHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Split drag handle

/// A slim gutter between master/detail panes that drags the sidebar width,
/// macOS-split-view style. Implemented as a real NSView so the drag wins even
/// in windows with `isMovableByWindowBackground = true` — a SwiftUI
/// DragGesture loses that race because AppKit claims the mouseDown as a
/// window-background drag before the gesture's minimum distance is met.
struct SplitDragHandle: NSViewRepresentable {
    @Binding var width: Double
    let range: ClosedRange<Double>

    func makeNSView(context: Context) -> SplitDragNSView {
        let view = SplitDragNSView()
        view.onBegin = { context.coordinator.startWidth = width }
        view.onDrag = { delta in
            let proposed = context.coordinator.startWidth + delta
            width = min(max(proposed, range.lowerBound), range.upperBound)
        }
        return view
    }

    func updateNSView(_ nsView: SplitDragNSView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SplitDragNSView, context: Context) -> CGSize? {
        CGSize(width: 16, height: proposal.height ?? 100)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var startWidth: Double = 0
    }
}

final class SplitDragNSView: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((Double) -> Void)?

    private var startMouseX: CGFloat = 0

    // The whole point: without this, a window with
    // isMovableByWindowBackground treats our mouseDown as "drag the window".
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        startMouseX = NSEvent.mouseLocation.x
        onBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        onDrag?(NSEvent.mouseLocation.x - startMouseX)
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}
