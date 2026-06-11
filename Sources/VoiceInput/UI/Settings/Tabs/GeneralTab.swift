import SwiftUI

/// General settings: master enable toggle and the ASR language hints.
struct GeneralTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                InlineRow(
                    title: "Enable voice input",
                    help: "Master switch for the global hotkey and dictation."
                ) {
                    BlueToggle(isOn: $settings.appEnabled)
                }

                Hairline()

                FieldRow(
                    title: "Language hints",
                    help: "ISO codes, e.g. zh,en — passed to Soniox as language_hints."
                ) {
                    FilledTextField(
                        placeholder: "zh,en",
                        text: $settings.languageHints,
                        monospaced: true
                    )
                }
            }
        }
    }
}
