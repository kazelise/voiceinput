import SwiftUI

/// Permission status rows for Microphone and Accessibility, each with a status
/// glyph and a context-appropriate Grant / Open Settings action.
struct PermissionsTab: View {
    @EnvironmentObject private var permissions: PermissionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                PermissionRow(
                    symbol: "mic.fill",
                    title: "Microphone",
                    subtitle: "Required to capture your voice for transcription.",
                    state: permissions.microphone,
                    action: { permissions.grantMicrophone() }
                )
                Hairline()
                PermissionRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    subtitle: "Required to suppress Fn and auto-paste transcribed text.",
                    state: permissions.accessibility,
                    action: { permissions.grantAccessibility() }
                )
            }
        }
        .onAppear { permissions.refresh() }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let state: PermissionStatus.State
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            statusGlyph

            if state != .granted {
                Button(buttonLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch state {
        case .granted:
            Label("Granted", systemImage: "checkmark.seal.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.green)
        case .notDetermined:
            Label("Not set", systemImage: "questionmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        case .denied:
            Label("Denied", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
                .foregroundStyle(Color.orange)
        }
    }

    private var buttonLabel: String {
        switch state {
        case .granted:       return ""
        case .notDetermined: return "Grant Access"
        case .denied:        return "Open Settings"
        }
    }
}
