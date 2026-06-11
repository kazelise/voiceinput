import SwiftUI

/// The six settings tabs, in System-Settings order, each with its line icon.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case hotkey
    case providers
    case vocabulary
    case appearance
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .hotkey:      return "Hotkey"
        case .providers:   return "Providers"
        case .vocabulary:  return "Vocabulary"
        case .appearance:  return "Appearance"
        case .permissions: return "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general:     return "gear"
        case .hotkey:      return "command"
        case .providers:   return "server.rack"
        case .vocabulary:  return "character.book.closed"
        case .appearance:  return "sparkles"
        case .permissions: return "lock.shield"
        }
    }
}

/// Root of the Settings window content: centered bold title, the horizontal
/// icon-tab strip with a pill selection, a hairline, then the selected tab.
struct SettingsRootView: View {
    let refiner: Refiner

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var vocabulary: VocabularyStore
    @EnvironmentObject private var permissions: PermissionStatus

    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            Hairline()
            content
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(Theme.chrome.ignoresSafeArea())
    }

    // MARK: Title

    private var header: some View {
        Text("Settings")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 14)
    }

    // MARK: Icon-tab strip

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(height: 20)
                Text(tab.title)
                    .font(.system(size: 12, weight: .regular))
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
            .frame(width: 84, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.pill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tab content

    @ViewBuilder
    private var content: some View {
        ScrollView(.vertical) {
            Group {
                switch selection {
                case .general:     GeneralTab()
                case .hotkey:      HotkeyTab()
                case .providers:   ProvidersTab(refiner: refiner)
                case .vocabulary:  VocabularyTab()
                case .appearance:  AppearanceTab()
                case .permissions: PermissionsTab()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}
