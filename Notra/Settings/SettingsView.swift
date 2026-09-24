import Foundation
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
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
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
struct SettingsCategoryRow: View {
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
struct SettingsHeaderView: View {
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

extension View {
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

#Preview {
    SettingsView(store: NotesStore(repository: TextBundleNoteRepository(rootURL: .temporaryDirectory)))
}
