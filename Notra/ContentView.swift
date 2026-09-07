import SwiftUI

/// Owns the app's split-view shell and connects note-store state to its sidebar and editor.
struct ContentView: View {
    /// Shared store bound into both columns of the split view.
    @Bindable var store: NotesStore
    /// Lets the system manage sidebar visibility while the split view has regular width.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// Chooses which split-view column receives compact-width navigation.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    /// Search query owned by the sidebar, cleared after a new note is created.
    @State private var searchText = ""
    /// Toggles the editor/preview mode on the detail column.
    @State private var isEditing = false
    /// Keeps inspector presentation at the split-view boundary, shared by every platform.
    @State private var isAttachmentInspectorPresented = false
    /// Carries an inspector insertion into the editor, which consumes and clears the request.
    @State private var attachmentToInsert: TextBundleAsset?
    /// Monotonic request that moves focus into a newly created note.
    @State private var editorFocusRequest = 0
    /// Monotonic request carrying a selected imported attachment into the editor.
    @State private var attachmentSelectionRequest = MarkdownAttachmentSelectionRequest.empty
    /// Presentation state for the shared attachment file importer.
    @State private var isAttachmentFileImporterPresented = false
    /// User-selected initial Markdown for new note creation.
    @AppStorage(NoteSettingKey.startNewNoteWith) private var startNewNoteWith =
        NoteStartContent.defaultValue.rawValue

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            NotesSidebar(
                store: store,
                isEditing: isEditing,
                searchText: $searchText,
                createNote: createNote
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            NoteEditorPane(
                store: store,
                isEditing: $isEditing,
                isAttachmentInspectorPresented: $isAttachmentInspectorPresented,
                attachmentToInsert: $attachmentToInsert,
                editorFocusRequest: editorFocusRequest,
                createNote: createNote,
                attachmentSelectionRequest: attachmentSelectionRequest,
                requestAttachmentSelection: presentAttachmentFileImporter
            )
        }
        .navigationSplitViewStyle(.prominentDetail)
        // Placing the inspector outside the split view preserves its system sidebar navigation.
        // An inspector on the detail content can hide the sidebar toggle on iPadOS 26.
        .inspector(isPresented: $isAttachmentInspectorPresented) {
            AttachmentInspectorView(
                store: store,
                isEditing: isEditing,
                insertAttachment: { attachmentToInsert = $0 },
                removeTag: removeTag
            )
        }
        .task {
            await store.loadNotes()
        }
        .onChange(of: store.selectedNoteID) {
            attachmentToInsert = nil
            if !store.hasSelection {
                isAttachmentInspectorPresented = false
            }
            Task {
                await store.selectionChanged()
            }
        }
        .alert("Notra", isPresented: errorBinding) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .modifier(attachmentFileImporter)
    }

    /// Routes inspector tag changes through the same store used by the sidebar and editor.
    private func removeTag(_ tag: NoteTag) {
        Task {
            await store.removeTag(tag)
        }
    }

    /// Adapts the store's optional error into the Boolean binding expected by `alert`.
    private var errorBinding: Binding<Bool> {
        Binding {
            store.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                store.errorMessage = nil
            }
        }
    }

    /// Creates a note and moves compact layouts into focused editing when selection changes.
    private func createNote() {
        Task {
            let previousSelectionID = store.selectedNoteID
            let startContent = NoteStartContent.resolved(rawValue: startNewNoteWith)
            await store.createNote(initialMarkdown: startContent.initialMarkdown)
            searchText = ""
            guard store.selectedNoteID != previousSelectionID else {
                return
            }

            preferredCompactColumn = .detail
            isEditing = true
            editorFocusRequest += 1
        }
    }

    /// Builds the importer modifier while keeping imported URLs in the root content state.
    private var attachmentFileImporter: AttachmentFileImporterModifier {
        AttachmentFileImporterModifier(isPresented: $isAttachmentFileImporterPresented) { url in
            attachmentSelectionRequest = MarkdownAttachmentSelectionRequest(
                id: attachmentSelectionRequest.id + 1,
                url: url
            )
        } onError: { error in
            store.errorMessage = error.localizedDescription
        }
    }

    /// Requests platform file selection for an attachment link.
    private func presentAttachmentFileImporter() {
        AppLog.info("Presenting attachment file importer from root content")
        isAttachmentFileImporterPresented = true
    }
}

#Preview {
    ContentView(store: NotesStore(repository: TextBundleNoteRepository(rootURL: .temporaryDirectory)))
}
