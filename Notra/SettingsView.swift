import SwiftUI

/// Hosts the settings navigation shell and platform-specific appearance controls.
struct SettingsView: View {
    @Bindable var store: NotesStore

    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    /// Persisted editor font family passed to both native editor bridges.
    @AppStorage(AppearanceSettingKey.editorFontName) private var editorFontName = AppearanceFont.defaultName
    /// Persisted editor point size.
    @AppStorage(AppearanceSettingKey.editorFontSize) private var editorFontSize = AppearanceFont.defaultSize
    /// Persisted preview font family.
    @AppStorage(AppearanceSettingKey.previewFontName) private var previewFontName = AppearanceFont.defaultName
    /// Whether the Markdown preview follows the editor's selected syntax theme.
    @AppStorage(AppearanceSettingKey.previewUsesEditorTheme) private var previewUsesEditorTheme = true
    /// Whether note rows include their content preview below the title or first line.
    @AppStorage(AppearanceSettingKey.showsNotePreview) private var showsNotePreview = true
    /// Maximum attachment size enforced before an import reaches storage.
    @AppStorage(AttachmentSettingKey.maximumSizeMB) private var maximumAttachmentSizeMB =
        AttachmentSettings.defaultMaximumSizeMB
    /// Initial Markdown template applied when users create a new note.
    @AppStorage(NoteSettingKey.startNewNoteWith) private var startNewNoteWith =
        NoteStartContent.defaultValue.rawValue

    #if os(macOS)
    @State private var selectedCategory = SettingsCategory.general
    #endif

    var body: some View {
        #if os(macOS)
        macSettingsView
        #else
        iOSSettingsView
        #endif
    }

    #if os(iOS)
    private var iOSSettingsView: some View {
        NavigationStack {
            List(SettingsCategory.allCases) { category in
                NavigationLink(value: category) {
                    SettingsCategoryRow(category: category)
                }
            }
            .settingsCategoryListStyle()
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsCategory.self) { category in
                settingsDetail(for: category, showsHeader: true)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }
    #endif

    #if os(macOS)
    private var macSettingsView: some View {
        TabView(selection: $selectedCategory) {
            Tab(
                SettingsCategory.general.title,
                systemImage: SettingsCategory.general.systemImage,
                value: .general
            ) {
                settingsDetail(for: .general, showsHeader: false)
            }

            Tab(
                SettingsCategory.appearance.title,
                systemImage: SettingsCategory.appearance.systemImage,
                value: .appearance
            ) {
                settingsDetail(for: .appearance, showsHeader: false)
            }

            Tab(
                SettingsCategory.about.title,
                systemImage: SettingsCategory.about.systemImage,
                value: .about
            ) {
                settingsDetail(for: .about, showsHeader: false)
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 420, idealHeight: 500)
    }
    #endif

    @ViewBuilder
    private func settingsDetail(for category: SettingsCategory, showsHeader: Bool) -> some View {
        switch category {
        case .general:
            GeneralSettingsDetailView(
                store: store,
                startNewNoteWith: $startNewNoteWith,
                maximumAttachmentSizeMB: $maximumAttachmentSizeMB,
                showsNotePreview: $showsNotePreview,
                showsHeader: showsHeader
            )
        case .appearance:
            AppearanceSettingsDetailView(
                editorFontName: $editorFontName,
                editorFontSize: $editorFontSize,
                previewFontName: $previewFontName,
                previewUsesEditorTheme: $previewUsesEditorTheme,
                showsHeader: showsHeader
            )
        case .about:
            AboutSettingsDetailView(info: .current, showsHeader: showsHeader)
        }
    }
}

/// The categories displayed in the settings sidebar or top-level iOS tabs.
private enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general:
            "General"
        case .appearance:
            "Appearance"
        case .about:
            "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .appearance:
            "textformat.size"
        case .about:
            "info.circle"
        }
    }

    var description: String {
        switch self {
        case .general:
            "Configure common note and attachment behaviour."
        case .appearance:
            "Choose how notes look while editing and previewing."
        case .about:
            "View app version and note format information."
        }
    }
}

#if os(iOS)
/// Renders one settings category with consistent icon and selection treatment.
private struct SettingsCategoryRow: View {
    let category: SettingsCategory

    var body: some View {
        Label {
            Text(category.title)
        } icon: {
            Image(systemName: category.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }
}
#endif

/// Provides the macOS settings header used above the category list.
private struct SettingsHeaderView: View {
    let category: SettingsCategory

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(category.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(category.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Contains general storage, attachment, and behavior preferences.
private struct GeneralSettingsDetailView: View {
    @Bindable var store: NotesStore
    @Binding var startNewNoteWith: String
    @Binding var maximumAttachmentSizeMB: Int
    @Binding var showsNotePreview: Bool
    let showsHeader: Bool

    var body: some View {
        Form {
            if showsHeader {
                SettingsHeaderView(category: .general)
                    .settingsHeaderFormRow()
            }

            Section {
                Picker("Notes Location", selection: storageLocationBinding) {
                    ForEach(NoteStorageLocation.allCases) { location in
                        Text(location.title)
                            .tag(location)
                            .disabled(location == .iCloud && !store.isICloudStorageAvailable)
                    }
                }
                .disabled(store.isChangingStorage)
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif
            } header: {
                Text("Notes")
            } footer: {
                Text("Choose where notes are stored. Changing location does not move existing notes.")
            }

            Section {
                Picker("Start New Note With", selection: $startNewNoteWith) {
                    ForEach(NoteStartContent.allCases) { option in
                        Text(option.title)
                            .tag(option.rawValue)
                    }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif
            } footer: {
                Text("Choose whether new notes begin with a title heading or an empty document.")
            }

            Section {
                Toggle("Show Note Preview", isOn: $showsNotePreview)
            } footer: {
                Text("Show each note’s first line or content preview in the notes list.")
            }

            Section {
                Stepper(
                    value: maximumAttachmentSizeBinding,
                    in: AttachmentSettings.supportedMaximumSizeRange,
                    step: AttachmentSettings.maximumSizeStep
                ) {
                    LabeledContent("Maximum Attachment Size") {
                        Text("\(maximumAttachmentSizeMB.formatted(.number)) MB")
                    }
                }
            } footer: {
                Text("Files larger than this limit cannot be added to a note.")
            }
        }
        .settingsDetailFormStyle()
        .settingsDetailNavigationTitle(SettingsCategory.general.title)
    }

    private var maximumAttachmentSizeBinding: Binding<Int> {
        Binding {
            AttachmentSettings.clampedMaximumSizeMB(maximumAttachmentSizeMB)
        } set: { newValue in
            maximumAttachmentSizeMB = AttachmentSettings.clampedMaximumSizeMB(newValue)
        }
    }

    private var storageLocationBinding: Binding<NoteStorageLocation> {
        Binding {
            store.storageLocation
        } set: { location in
            Task {
                await store.changeStorageLocation(to: location)
            }
        }
    }
}

/// Contains editor, preview, theme, and font appearance preferences.
private struct AppearanceSettingsDetailView: View {
    @Binding var editorFontName: String
    @Binding var editorFontSize: Double
    @Binding var previewFontName: String
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
                Toggle("Colourful Preview", isOn: $previewUsesEditorTheme)
            } header: {
                Text("Preview")
            } footer: {
                Text("Use the editor’s syntax colours when rendering note previews.")
            }
        }
        .settingsDetailFormStyle()
        .settingsDetailNavigationTitle(SettingsCategory.appearance.title)
        .onAppear(perform: normaliseFontSelections)
    }

    private func fontChoices(fixedPitchOnly: Bool) -> some View {
        ForEach(AppearanceFont.availableChoices(fixedPitchOnly: fixedPitchOnly)) { choice in
            Text(choice.displayName)
                .tag(choice.fontName)
        }
    }

    /// Keeps persisted names valid when a previously selected system font is removed.
    private func normaliseFontSelections() {
        let editorChoices = AppearanceFont.availableChoices(fixedPitchOnly: true)
        let previewChoices = AppearanceFont.availableChoices(fixedPitchOnly: false)

        editorFontName = AppearanceFont.resolvedName(editorFontName, choices: editorChoices)
        previewFontName = AppearanceFont.resolvedName(previewFontName, choices: previewChoices)
    }
}

/// Displays app identity, version, and open-source attribution information.
private struct AboutSettingsDetailView: View {
    let info: AppAboutInfo
    let showsHeader: Bool

    var body: some View {
        Form {
            if showsHeader {
                SettingsHeaderView(category: .about)
                    .settingsHeaderFormRow()
            }

            Section {
                LabeledContent("Application", value: info.displayName)
                LabeledContent("Version", value: info.versionDisplay)
                LabeledContent("Format", value: "TextBundle notes")
            } header: {
                Text("App Information")
            }
        }
        .settingsDetailFormStyle()
        .settingsDetailNavigationTitle(SettingsCategory.about.title)
    }
}

/// Collects bundle metadata once so the About view can render missing values safely.
private struct AppAboutInfo {
    let displayName: String
    let version: String
    let build: String

    static var current: AppAboutInfo {
        let bundle = Bundle.main
        return AppAboutInfo(
            displayName: bundle.stringValue(for: "CFBundleDisplayName")
                ?? bundle.stringValue(for: "CFBundleName")
                ?? "Notra",
            version: bundle.stringValue(for: "CFBundleShortVersionString") ?? "1.0",
            build: bundle.stringValue(for: "CFBundleVersion") ?? "1"
        )
    }

    var versionDisplay: String {
        "Version \(version) (\(build))"
    }
}

private extension View {
    @ViewBuilder
    func settingsCategoryListStyle() -> some View {
        #if os(macOS)
        listStyle(.sidebar)
        #else
        listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    func settingsDetailFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    func settingsHeaderFormRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    func settingsDetailNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle(title)
        #else
        self
        #endif
    }
}

private extension Bundle {
    func stringValue(for key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }
}

#Preview {
    SettingsView(store: NotesStore(repository: TextBundleNoteRepository(rootURL: .temporaryDirectory)))
}
