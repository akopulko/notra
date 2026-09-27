import SwiftUI

/// Contains editor, preview, theme, and font appearance preferences.
struct AppearanceSettingsDetailView: View {
    @Binding var editorFontName: String
    @Binding var editorFontSize: Double
    @Binding var previewFontName: String
    @Binding var previewFixedWidthFontName: String
    @Binding var previewUsesEditorTheme: Bool
    let showsHeader: Bool

    var body: some View {
        Form {
            if showsHeader {
                SettingsHeaderView(category: .appearance)
                    .settingsHeaderFormRow()
            }

            Section {
                Picker("Editor Font", selection: $editorFontName) {
                    fontChoices(fixedPitchOnly: true)
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif
            } header: {
                Text("Fonts")
            } footer: {
                Text("Choose the monospaced font used while editing Markdown.")
            }

            Section {
                Stepper(value: $editorFontSize, in: 12...28, step: 1) {
                    LabeledContent("Editor Font Size") {
                        Text(editorFontSize.formatted(.number.precision(.fractionLength(0))) + " pt")
                    }
                }
            } footer: {
                Text("Adjust the text size used in the editor.")
            }

            Section {
                Picker("Preview Font", selection: $previewFontName) {
                    fontChoices(fixedPitchOnly: false)
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif
            } footer: {
                Text("Choose the font used when reading note previews.")
            }

            Section {
                Picker("Preview Fixed Width Font", selection: $previewFixedWidthFontName) {
                    fontChoices(fixedPitchOnly: true)
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif
            } footer: {
                Text("Choose the monospaced font used for inline code and code blocks in note previews.")
            }

            Section {
                Toggle("Colourful Preview", isOn: $previewUsesEditorTheme)
            } header: {
                Text("Preview")
            } footer: {
                Text("Use the editor’s syntax colours when rendering note previews.")
            }
        }
        .settingsDetailFormStyle()
        .settingsDetailNavigationTitle(SettingsCategory.appearance.title)
        .onAppear {
            AppearanceFont.invalidateAvailableChoices()
            normaliseFontSelections()
        }
    }

    private func fontChoices(fixedPitchOnly: Bool) -> some View {
        ForEach(AppearanceFont.availableChoices(fixedPitchOnly: fixedPitchOnly)) { choice in
            if choice.fontName.isEmpty {
                Text(AppearanceFont.defaultDisplayName)
                    .tag(choice.fontName)
            } else {
                Text(verbatim: choice.displayName)
                    .tag(choice.fontName)
            }
        }
    }

    /// Keeps persisted names valid when a previously selected system font is removed.
    private func normaliseFontSelections() {
        let editorChoices = AppearanceFont.availableChoices(fixedPitchOnly: true)
        let previewChoices = AppearanceFont.availableChoices(fixedPitchOnly: false)
        let fixedWidthChoices = AppearanceFont.availableChoices(fixedPitchOnly: true)

        editorFontName = AppearanceFont.resolvedName(editorFontName, choices: editorChoices)
        previewFontName = AppearanceFont.resolvedName(previewFontName, choices: previewChoices)
        previewFixedWidthFontName = AppearanceFont.resolvedName(
            previewFixedWidthFontName,
            choices: fixedWidthChoices
        )
    }
}
