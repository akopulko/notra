import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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
    /// Persisted fixed-width font family used for code in note previews.
    @AppStorage(AppearanceSettingKey.previewFixedWidthFontName) private var previewFixedWidthFontName =
        AppearanceFont.defaultName
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
            List {
                ForEach(SettingsCategory.allCases) { category in
                    NavigationLink(value: category) {
                        SettingsCategoryRow(category: category)
                    }
                }

                Section {
                    NavigationLink {
                        KeyboardShortcutsView()
                    } label: {
                        Label("Keyboard Shortcuts", systemImage: "keyboard")
                    }
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
                previewFixedWidthFontName: $previewFixedWidthFontName,
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
            "Version, links and project information."
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

    @State private var libraryByteCount: Int64?
    @State private var isLoadingLibraryByteCount = true

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

                LabeledContent {
                    Text(store.notes.count, format: .number)
                } label: {
                    Text("Notes", comment: "Settings row showing the number of notes in the active library.")
                }

                LabeledContent {
                    if isLoadingLibraryByteCount {
                        ProgressView()
                    } else if let libraryByteCount {
                        Text(ByteCountFormatter.string(fromByteCount: libraryByteCount, countStyle: .file))
                    } else {
                        Text("Unavailable", comment: "Settings value shown when the library size cannot be read.")
                    }
                } label: {
                    Text("Library Size", comment: "Settings row showing the total size of the active notes library.")
                }

                #if os(macOS)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([store.libraryURL])
                } label: {
                    Label {
                        Text("Open Library Location", comment: "Button that reveals the active notes library in Finder.")
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
                .disabled(store.isChangingStorage)
                #else
                LabeledContent {
                    Text(store.storageDescription)
                } label: {
                    Text("Library Location", comment: "Settings row showing where the active notes library appears in Files.")
                }
                #endif
            } header: {
                Text("Notes")
            } footer: {
                VStack(alignment: .leading) {
                    Text("Choose where notes are stored. Changing location does not move existing notes.")
                    #if os(iOS)
                    Text(
                        "The library is available in the Files app.",
                        comment: "Explains where iOS users can find the active notes library."
                    )
                    #endif
                }
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
        .task(id: store.libraryURL) {
            libraryByteCount = nil
            isLoadingLibraryByteCount = true

            do {
                let byteCount = try await store.loadLibraryByteCount()
                guard !Task.isCancelled else {
                    return
                }
                libraryByteCount = byteCount
                isLoadingLibraryByteCount = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                isLoadingLibraryByteCount = false
            }
        }
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
            Text(choice.displayName)
                .tag(choice.fontName)
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

/// Displays app identity, version, and open-source attribution information.
private struct AboutSettingsDetailView: View {
    let info: AppAboutInfo
    let showsHeader: Bool

    var body: some View {
        Form {
            AboutHeroView(info: info)
                .settingsHeaderFormRow()

            Section {
                LabeledContent("Version", value: info.versionDisplay)
                LabeledContent("Format", value: "Markdown + TextBundle")
                LabeledContent("Platforms", value: "Mac, iPhone and iPad")
            } header: {
                Text("About Notra")
            }

            Section {
                Link(destination: info.websiteURL) {
                    Label("Website", systemImage: "safari")
                }

                Link(destination: info.sourceCodeURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } header: {
                Text("Project")
            }

            Section {
                AboutPrincipleRow(
                    title: "No account required",
                    subtitle: "Start writing without creating a profile.",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                AboutPrincipleRow(
                    title: "Portable notes",
                    subtitle: "Markdown and TextBundle files stay useful outside Notra.",
                    systemImage: "doc.text"
                )
                AboutPrincipleRow(
                    title: "Open source",
                    subtitle: "The project is available on GitHub.",
                    systemImage: "curlybraces"
                )
            } header: {
                Text("Principles")
            }
        }
        .settingsDetailFormStyle()
        .settingsDetailNavigationTitle(SettingsCategory.about.title)
    }
}

private struct AboutHeroView: View {
    let info: AppAboutInfo

    var body: some View {
        VStack(spacing: 14) {
            AboutAppIconView()

            Text(info.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Notes that stay yours.")
                .font(.headline)

            Text("Private Markdown notes for Mac, iPhone and iPad.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct AboutAppIconView: View {
    var body: some View {
        #if os(iOS)
        if let image = primaryIcon {
            iconView(Image(uiImage: image))
        } else {
            fallbackIconView
        }
        #else
        if let image = NSApplication.shared.applicationIconImage, image.size != .zero {
            iconView(Image(nsImage: image))
        } else {
            fallbackIconView
        }
        #endif
    }

    #if os(iOS)
    private var primaryIcon: UIImage? {
        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else {
            return nil
        }

        return UIImage(named: iconName)
    }
    #endif

    private func iconView(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private var fallbackIconView: some View {
        Image(systemName: "note.text")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 76, height: 76)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
}

private struct AboutPrincipleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }
}

/// Collects bundle metadata once so the About view can render missing values safely.
private struct AppAboutInfo {
    let displayName: String
    let version: String
    let build: String
    let websiteURL: URL
    let sourceCodeURL: URL

    static var current: AppAboutInfo {
        let bundle = Bundle.main
        return AppAboutInfo(
            displayName: bundle.stringValue(for: "CFBundleDisplayName")
                ?? bundle.stringValue(for: "CFBundleName")
                ?? "Notra",
            version: bundle.stringValue(for: "CFBundleShortVersionString") ?? "1.0",
            build: bundle.stringValue(for: "CFBundleVersion") ?? "1",
            websiteURL: URL(string: "https://notra-app.cc/")!,
            sourceCodeURL: URL(string: "https://github.com/akopulko/notra")!
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
