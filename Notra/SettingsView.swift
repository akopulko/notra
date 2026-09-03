import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Hosts the settings navigation shell and platform-specific appearance controls.
struct SettingsView: View {
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
        .background(SettingsWindowCenteringView())
    }
    #endif

    @ViewBuilder
    private func settingsDetail(for category: SettingsCategory, showsHeader: Bool) -> some View {
        switch category {
        case .general:
            GeneralSettingsDetailView(
                startNewNoteWith: $startNewNoteWith,
                maximumAttachmentSizeMB: $maximumAttachmentSizeMB,
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
    @Binding var startNewNoteWith: String
    @Binding var maximumAttachmentSizeMB: Int
    let showsHeader: Bool

    var body: some View {
        Form {
            if showsHeader {
                SettingsHeaderView(category: .general)
                    .settingsHeaderFormRow()
            }

            Section {
                Picker("Start New Note With", selection: $startNewNoteWith) {
                    ForEach(NoteStartContent.allCases) { option in
                        Text(option.title)
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Notes")
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
            } header: {
                Text("Attachments")
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

                Stepper(value: $editorFontSize, in: 12...28, step: 1) {
                    LabeledContent("Editor Font Size") {
                        Text(editorFontSize.formatted(.number.precision(.fractionLength(0))) + " pt")
                    }
                }

                Picker("Preview Font", selection: $previewFontName) {
                    fontChoices(fixedPitchOnly: false)
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #else
                .pickerStyle(.navigationLink)
                #endif
            } header: {
                Text("Fonts")
            }

            Section {
                Toggle("Apply Editor Theme Colors to Preview", isOn: $previewUsesEditorTheme)
            } header: {
                Text("Preview")
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

#if os(macOS)
private enum SettingsWindowMetrics {
    static let contentSize = NSSize(width: 350, height: 450)
}

private struct SettingsWindowCenteringView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        Task { @MainActor [weak nsView, coordinator] in
            guard let window = nsView?.window else {
                return
            }

            coordinator.center(window)
        }
    }

    @MainActor
    final class Coordinator {
        private var centeredWindowIDs = Set<ObjectIdentifier>()

        func center(_ settingsWindow: NSWindow) {
            let settingsWindowID = ObjectIdentifier(settingsWindow)
            guard !centeredWindowIDs.contains(settingsWindowID),
                  let referenceWindow = referenceWindow(for: settingsWindow)
            else {
                return
            }

            settingsWindow.setContentSize(SettingsWindowMetrics.contentSize)

            let referenceFrame = referenceWindow.frame
            let settingsFrame = settingsWindow.frame
            var origin = NSPoint(
                x: referenceFrame.midX - settingsFrame.width / 2,
                y: referenceFrame.midY - settingsFrame.height / 2
            )

            if let visibleFrame = referenceWindow.screen?.visibleFrame {
                origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - settingsFrame.width)
                origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - settingsFrame.height)
            }

            settingsWindow.setFrameOrigin(origin)
            centeredWindowIDs.insert(settingsWindowID)
        }

        private func referenceWindow(for settingsWindow: NSWindow) -> NSWindow? {
            let candidates = NSApp.windows.filter { window in
                window !== settingsWindow
                    && window.isVisible
                    && !window.isMiniaturized
                    && window.level == .normal
            }

            return candidates.first { $0.title == "Notra" }
                ?? candidates.first { $0.canBecomeMain }
        }
    }
}
#endif

#Preview {
    SettingsView()
}
