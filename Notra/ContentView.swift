import SwiftUI

struct ContentView: View {
    @Bindable var store: NotesStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var searchText = ""
    @State private var isEditing = false
    @State private var editorFocusRequest = 0
    @State private var attachmentSelectionRequest = MarkdownAttachmentSelectionRequest.empty
    @State private var isAttachmentFileImporterPresented = false

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
                editorFocusRequest: editorFocusRequest,
                createNote: createNote,
                attachmentSelectionRequest: attachmentSelectionRequest,
                requestAttachmentSelection: presentAttachmentFileImporter
            )
        }
        .task {
            await store.loadNotes()
        }
        .onChange(of: store.selectedNoteID) {
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

    private var errorBinding: Binding<Bool> {
        Binding {
            store.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                store.errorMessage = nil
            }
        }
    }

    private func createNote() {
        Task {
            let previousSelectionID = store.selectedNoteID
            await store.createNote()
            searchText = ""
            guard store.selectedNoteID != previousSelectionID else {
                return
            }

            preferredCompactColumn = .detail
            isEditing = true
            editorFocusRequest += 1
        }
    }

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

    private func presentAttachmentFileImporter() {
        AppLog.info("Presenting attachment file importer from root content")
        isAttachmentFileImporterPresented = true
    }
}

#Preview {
    ContentView(store: NotesStore(repository: TextBundleNoteRepository(rootURL: .temporaryDirectory)))
}
