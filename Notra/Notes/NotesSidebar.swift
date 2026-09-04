import SwiftUI
import UniformTypeIdentifiers

/// Owns the searchable, sortable note list and its context-menu export actions.
struct NotesSidebar: View {
    @Bindable var store: NotesStore
    let isEditing: Bool
    @Binding var searchText: String
    let createNote: () -> Void
    @Namespace private var settingsZoom
    @State private var isSearchPresented = false
    @State private var searchResultIDs: [URL] = []
    @State private var hasMoreSearchResults = false
    @State private var isLoadingMoreSearchResults = false
    @State private var exportTask: Task<Void, Never>?
    @AppStorage(AppearanceSettingKey.previewFontName) private var previewFontName = AppearanceFont.defaultName
    @AppStorage(AppearanceSettingKey.showsNotePreview) private var showsNotePreview = true
    #if os(iOS)
    @State private var isSettingsPresented = false
    #else
    @State private var pendingFileExport: PendingNoteFileExport?
    #endif

    var body: some View {
        notesList
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    NewNoteButton(action: createNote)
                    SortNotesMenu(
                        preference: store.sortPreference,
                        setField: store.setSortField,
                        setDirection: store.setSortDirection
                    )
                    #if os(iOS)
                    settingsButton
                    #endif
                }
                DefaultToolbarItem(kind: .search, placement: .automatic)
            }
            .searchable(text: $searchText, isPresented: searchPresentation, prompt: "Search Notes")
            #if os(iOS)
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            #else
            .fileExporter(
                isPresented: Binding(
                    get: { pendingFileExport != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingFileExport = nil
                        }
                    }
                ),
                document: pendingFileExport?.document,
                contentType: pendingFileExport?.contentType ?? .data,
                defaultFilename: pendingFileExport?.suggestedFilename
            ) { result in
                if case let .failure(error) = result {
                    AppLog.error("Failed to save note export: \(error.localizedDescription)")
                    store.errorMessage = error.localizedDescription
                }
                pendingFileExport = nil
            }
            #endif
            .onChange(of: isEditing) {
                if isEditing {
                    searchText = ""
                    isSearchPresented = false
                }
            }
            .task(id: "\(trimmedSearchText)|\(String(describing: store.searchStatus))") {
                await refreshSearchResults()
            }
    }

    #if os(iOS)
    private var settingsButton: some View {
        Button("Settings", systemImage: "gear") {
            isSettingsPresented = true
        }
        .labelStyle(.iconOnly)
        .matchedTransitionSource(id: "settings", in: settingsZoom)
    }
    #endif

    private var notesList: some View {
        List(selection: $store.selectedNoteID) {
            ForEach(visibleNotes) { note in
                NavigationLink(value: note.id) {
                    NoteRow(
                        note: note,
                        sortField: store.sortPreference.field,
                        showsNotePreview: showsNotePreview
                    )
                }
                .contextMenu {
                    Button("Share…", systemImage: "square.and.arrow.up") {
                        sharePDF(note)
                    }
                    .disabled(isEditing)
                    #if os(macOS)
                    Menu("Export…", systemImage: "arrow.forward.folder.fill") {
                        Button("PDF") {
                            exportPDF(note)
                        }
                        Button("Markdown") {
                            exportMarkdown(note)
                        }
                    }
                    .disabled(isEditing)
                    #endif
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task {
                            await store.deleteNotes([note])
                        }
                    }
                }
                .listRowSeparator(.visible, edges: .bottom)
            }
            .onDelete { offsets in
                Task {
                    await store.deleteNotes(offsets.map { visibleNotes[$0] })
                }
            }
            if isSearching, hasMoreSearchResults {
                loadMoreRow
            }
        }
        .listStyle(.sidebar)
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .overlay {
            if store.notes.isEmpty, !store.isLoading {
                ContentUnavailableView {
                    Label("No Notes", systemImage: "note.text")
                } description: {
                    Text("Create a note to start writing.")
                } actions: {
                    Button("New Note", systemImage: "plus") {
                        createNote()
                    }
                }
            } else if visibleNotes.isEmpty, isSearching {
                searchEmptyState
            }
        }
    }

    private var visibleNotes: [NoteSummary] {
        guard isSearching else {
            return store.notes
        }

        let notesByBundleName = Dictionary(
            uniqueKeysWithValues: store.notes.map { ($0.url.lastPathComponent, $0) }
        )
        return searchResultIDs.compactMap { notesByBundleName[$0.lastPathComponent] }
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        switch store.searchStatus {
        case .notReady, .indexing:
            ProgressView("Indexing Notes...")
        case .ready:
            ContentUnavailableView.search(text: searchText)
        case .unavailable:
            ContentUnavailableView {
                Label("Search Unavailable", systemImage: "magnifyingglass")
            } description: {
                Text("The note search index could not be opened.")
            } actions: {
                Button("Retry Search", systemImage: "arrow.clockwise") {
                    store.retrySearchIndex()
                }
            }
        }
    }

    private var loadMoreRow: some View {
        Button {
            loadMoreSearchResults()
        } label: {
            if isLoadingMoreSearchResults {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label("Load More", systemImage: "ellipsis")
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(isLoadingMoreSearchResults)
        .listRowSeparator(.hidden)
    }

    @MainActor
    private func refreshSearchResults() async {
        searchResultIDs = []
        hasMoreSearchResults = false
        isLoadingMoreSearchResults = false

        guard isSearching else {
            return
        }

        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else {
            return
        }
        guard let page = await store.searchNotes(
            query: trimmedSearchText,
            limit: 50,
            offset: 0
        ) else {
            return
        }
        guard !Task.isCancelled else {
            return
        }

        let resultIDs = page.results.map(\.id)
        let noteBundleNames = Set(store.notes.map { $0.url.lastPathComponent })
        let mappedResultCount = resultIDs
            .map(\.lastPathComponent)
            .filter(noteBundleNames.contains)
            .count
        AppLog.debug(
            "Search UI received results; resultCount=\(resultIDs.count); "
                + "mappedResultCount=\(mappedResultCount); noteCount=\(store.notes.count)"
        )
        searchResultIDs = resultIDs
        hasMoreSearchResults = page.hasMore
    }

    private func loadMoreSearchResults() {
        guard isSearching, hasMoreSearchResults, !isLoadingMoreSearchResults else {
            return
        }

        let query = trimmedSearchText
        let offset = searchResultIDs.count
        Task { @MainActor in
            isLoadingMoreSearchResults = true
            defer { isLoadingMoreSearchResults = false }

            guard let page = await store.searchNotes(query: query, limit: 50, offset: offset) else {
                return
            }
            guard query == trimmedSearchText else {
                return
            }

            searchResultIDs.append(contentsOf: page.results.map(\.id))
            hasMoreSearchResults = page.hasMore
        }
    }

    private var searchPresentation: Binding<Bool> {
        Binding {
            !isEditing && isSearchPresented
        } set: { isPresented in
            isSearchPresented = !isEditing && isPresented
        }
    }

    private func sharePDF(_ note: NoteSummary) {
        prepareExport(for: note, format: .pdf, destination: .share)
    }

    #if os(macOS)
    private func exportPDF(_ note: NoteSummary) {
        prepareExport(for: note, format: .pdf, destination: .save)
    }

    private func exportMarkdown(_ note: NoteSummary) {
        prepareExport(for: note, format: .markdown, destination: .save)
    }
    #endif

    private func prepareExport(
        for note: NoteSummary,
        format: NoteExportFormat,
        destination: NoteExportDestination
    ) {
        guard !isEditing, exportTask == nil else {
            return
        }

        exportTask = Task { @MainActor in
            defer { exportTask = nil }

            do {
                let payload = try await store.exportPayload(for: note)
                switch format {
                case .pdf:
                    let item = try await NotePDFExporter().export(snapshot: pdfSnapshot(for: payload))
                    try present(
                        fileURL: item.fileURL,
                        contentType: .pdf,
                        suggestedFilename: item.suggestedFilename,
                        destination: destination
                    )
                case .markdown:
                    let item = try NoteMarkdownExporter().export(payload: payload)
                    try present(
                        fileURL: item.fileURL,
                        contentType: .notraMarkdown,
                        suggestedFilename: item.suggestedFilename,
                        destination: destination
                    )
                }
            } catch {
                AppLog.error("Failed to prepare note export: \(error.localizedDescription)")
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func pdfSnapshot(for payload: NoteExportPayload) -> NotePDFSnapshot {
        NotePDFSnapshot(
            markdown: payload.markdown,
            noteURL: payload.noteURL,
            previewFontName: previewFontName,
            suggestedFilename: payload.suggestedFilename
        )
    }

    private func present(
        fileURL: URL,
        contentType: UTType,
        suggestedFilename: String,
        destination: NoteExportDestination
    ) throws {
        switch destination {
        case .share:
            NoteSharePresenter.present(fileURL: fileURL)
        case .save:
            #if os(macOS)
            guard pendingFileExport == nil else {
                return
            }
            let data = try Data(contentsOf: fileURL)
            pendingFileExport = PendingNoteFileExport(
                document: NoteFileExportDocument(data: data),
                contentType: contentType,
                suggestedFilename: suggestedFilename
            )
            #endif
        }
    }
}

/// The file formats offered by the note-list export submenu.
private enum NoteExportFormat {
    case pdf
    case markdown
}

/// Identifies whether export is presented as a share sheet or a save panel.
private enum NoteExportDestination {
    case share
    case save
}
