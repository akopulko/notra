import SwiftUI

/// Owns the searchable, sortable note list and its context-menu export actions.
struct NotesSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: NotesStore
    let isEditing: Bool
    @Binding var searchText: String
    let createNote: () -> Void
    /// Shared export entry point used by row context menus and scene commands.
    let exportNote: (NoteSummary, NoteExportAction) -> Void
    #if os(iOS)
    @Namespace private var settingsZoom
    #endif
    @State private var isSearchPresented = false
    @State private var searchFilters: [NoteSearchFilter] = []
    #if os(macOS)
    /// Supplies the macOS search field with selectable prefilter tokens.
    @State private var suggestedSearchFilters = NoteSearchFilter.allCases
    #endif
    @State private var searchResultIDs: [URL] = []
    @State private var hasMoreSearchResults = false
    @State private var isLoadingMoreSearchResults = false
    /// Holds one user-initiated deletion until its native confirmation is resolved.
    @State private var pendingDeletion: NoteDeletionRequest?
    @AppStorage(AppearanceSettingKey.showsNotePreview) private var showsNotePreview = true
    #if os(iOS)
    @State private var isSettingsPresented = false
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
            #if os(macOS)
            .searchable(
                text: $searchText,
                tokens: $searchFilters,
                suggestedTokens: $suggestedSearchFilters,
                isPresented: searchPresentation,
                prompt: "Search Notes",
                token: searchToken
            )
            #else
            .searchable(
                text: $searchText,
                tokens: $searchFilters,
                isPresented: searchPresentation,
                prompt: "Search Notes",
                token: searchToken
            )
            #endif
            #if os(iOS)
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(store: store)
            }
            #endif
            .onChange(of: isEditing) {
                if isEditing {
                    searchText = ""
                    searchFilters = []
                    isSearchPresented = false
                }
            }
            .onChange(of: searchFilters) { _, filters in
                if filters.count > 1, let filter = filters.last {
                    searchFilters = [filter]
                }
                #if os(macOS)
                suggestedSearchFilters = NoteSearchFilter.allCases.filter { $0 != filters.last }
                #endif
            }
            .task(id: "\(trimmedSearchText)|\(selectedSearchFilter?.rawValue ?? "none")|\(String(describing: store.searchStatus))") {
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

    private func searchToken(for filter: NoteSearchFilter) -> some View {
        Label {
            Text(filter.title)
        } icon: {
            Image(systemName: filter.systemImage)
        }
    }

    private var notesList: some View {
        let groups = visibleNoteGroups

        return List(selection: $store.selectedNoteID) {
            if !groups.pinned.isEmpty {
                noteSection(
                    title: LocalizedStringResource(
                        "Pinned",
                        comment: "Sidebar section containing pinned notes."
                    ),
                    notes: groups.pinned
                )
            }

            if !groups.notes.isEmpty {
                noteSection(
                    title: LocalizedStringResource(
                        "Notes",
                        comment: "Sidebar section containing unpinned notes."
                    ),
                    notes: groups.notes
                )
            }

            if isSearching, hasMoreSearchResults {
                loadMoreRow
            }
        }
        .listStyle(.sidebar)
        .disabled(store.isChangingStorage)
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .overlay {
            ZStack(alignment: .top) {
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

                #if os(iOS)
                if showsSearchFilterSuggestions {
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()

                    searchFilterSuggestions
                }
                #endif
            }
        }
        .modifier(NoteDeletionConfirmationModifier(request: $pendingDeletion) { summaries in
            Task {
                await store.deleteNotes(summaries)
            }
        })
    }

    @MainActor
    private func refreshSearchResults() async {
        searchResultIDs = []
        hasMoreSearchResults = false
        isLoadingMoreSearchResults = false

        guard isSearching else {
            return
        }
        guard !trimmedSearchText.isEmpty else {
            return
        }

        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else {
            return
        }
        guard let page = await store.searchNotes(
            query: trimmedSearchText,
            filter: selectedSearchFilter,
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
        guard isSearching, !trimmedSearchText.isEmpty, hasMoreSearchResults, !isLoadingMoreSearchResults else {
            return
        }

        let query = trimmedSearchText
        let filter = selectedSearchFilter
        let offset = searchResultIDs.count
        Task { @MainActor in
            isLoadingMoreSearchResults = true
            defer { isLoadingMoreSearchResults = false }

            guard let page = await store.searchNotes(
                query: query,
                filter: filter,
                limit: 50,
                offset: offset
            ) else {
                return
            }
            guard query == trimmedSearchText, filter == selectedSearchFilter else {
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
}

private extension NotesSidebar {
    var searchFilterSuggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested")
                .font(.title3)

            VStack(spacing: 0) {
                ForEach(NoteSearchFilter.allCases) { filter in
                    VStack(spacing: 0) {
                        searchFilterSuggestionButton(for: filter)

                        if filter != .attachments {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(searchFilterCardBackground)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func searchFilterSuggestionButton(for filter: NoteSearchFilter) -> some View {
        Button {
            searchFilters = [filter]
        } label: {
            HStack(spacing: 12) {
                Image(systemName: filter.systemImage)
                    .font(.title2)
                    .frame(width: 40)
                    .foregroundStyle(tagColors.backgroundColor)

                Text(filter.title)
                    .font(.title3)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }

    var tagColors: MarkdownTagColors {
        MarkdownTheme.preferred(for: colorScheme).previewHashtagColors
    }

    #if os(iOS)
    var showsSearchFilterSuggestions: Bool {
        isSearchPresented && trimmedSearchText.isEmpty && searchFilters.isEmpty
    }

    var searchFilterCardBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }
    #else
    var searchFilterCardBackground: Color {
        .clear
    }
    #endif

    var visibleNotes: [NoteSummary] {
        guard isSearching else {
            return store.notes
        }

        guard !trimmedSearchText.isEmpty else {
            guard let selectedSearchFilter else {
                return store.notes
            }
            return store.notes.filter(selectedSearchFilter.matches)
        }

        let notesByBundleName = Dictionary(
            uniqueKeysWithValues: store.notes.map { ($0.url.lastPathComponent, $0) }
        )
        return NotePinning.pinnedFirst(
            searchResultIDs.compactMap { notesByBundleName[$0.lastPathComponent] }
        )
    }

    /// Partitions the already ordered list so each section preserves its existing sort semantics.
    var visibleNoteGroups: (pinned: [NoteSummary], notes: [NoteSummary]) {
        let notes = visibleNotes
        return (notes.filter(\.isPinned), notes.filter { !$0.isPinned })
    }

    var isSearching: Bool {
        !trimmedSearchText.isEmpty || selectedSearchFilter != nil
    }

    var selectedSearchFilter: NoteSearchFilter? {
        searchFilters.last
    }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    var searchEmptyState: some View {
        if trimmedSearchText.isEmpty, selectedSearchFilter != nil {
            ContentUnavailableView {
                Label("No Matching Notes", systemImage: "magnifyingglass")
            } description: {
                Text("Try removing the selected filter.")
            }
        } else {
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
    }

    var loadMoreRow: some View {
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

    func noteSection(title: LocalizedStringResource, notes: [NoteSummary]) -> some View {
        Section {
            ForEach(notes) { note in
                noteRow(note, showsBottomSeparator: note.id != notes.last?.id)
            }
            #if os(macOS)
            .onDelete { offsets in
                requestNoteDeletionForOffsets(offsets, in: notes)
            }
            #endif
        } header: {
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    func noteRow(_ note: NoteSummary, showsBottomSeparator: Bool) -> some View {
        NavigationLink(value: note.id) {
            NoteRow(
                note: note,
                sortField: store.sortPreference.field,
                showsNotePreview: showsNotePreview
            )
        }
        .contextMenu {
            NotePinContextMenuButton(note: note, isEditing: isEditing) {
                Task {
                    await store.togglePin(for: note)
                }
            }
            Divider()
            Button("Share…", systemImage: "square.and.arrow.up") {
                exportNote(note, .sharePDF)
            }
            .disabled(isEditing)
            Menu("Export…", systemImage: "arrow.forward.folder.fill") {
                Button("PDF") {
                    exportNote(note, .exportPDF)
                }
                Button("Markdown") {
                    exportNote(note, .exportMarkdown)
                }
            }
            .disabled(isEditing)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                requestNoteDeletion([note])
            }
        }
        .notePinSwipeAction(note: note) {
            Task {
                await store.togglePin(for: note)
            }
        }
        .noteDeletionSwipeAction {
            requestNoteDeletion([note])
        }
        .listRowSeparator(
            showsBottomSeparator ? .visible : .hidden,
            edges: .bottom
        )
    }

    /// Defers every user-facing deletion entry point to one confirmation dialog.
    func requestNoteDeletion(_ summaries: [NoteSummary]) {
        guard !summaries.isEmpty, pendingDeletion == nil else {
            return
        }

        pendingDeletion = NoteDeletionRequest(summaries: summaries)
    }

    func requestNoteDeletionForOffsets(_ offsets: IndexSet, in notes: [NoteSummary]) {
        requestNoteDeletion(offsets.map { notes[$0] })
    }
}

/// Provides the context-menu action that changes one note's persisted pin state.
private struct NotePinContextMenuButton: View {
    let note: NoteSummary
    let isEditing: Bool
    let action: () -> Void

    var body: some View {
        Button(
            note.isPinned ? "Unpin Note" : "Pin Note",
            systemImage: note.isPinned ? "pin.slash" : "pin",
            action: action
        )
        .disabled(isEditing)
    }
}

/// Captures the exact note rows selected before the list can change under a confirmation dialog.
private struct NoteDeletionRequest {
    let summaries: [NoteSummary]

    var message: String {
        summaries.count == 1
            ? "This note will be permanently deleted."
            : "These notes will be permanently deleted."
    }
}

/// Presents one native destructive alert before delegating to the existing store deletion path.
private struct NoteDeletionConfirmationModifier: ViewModifier {
    @Binding var request: NoteDeletionRequest?
    let delete: ([NoteSummary]) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Delete Note?",
            isPresented: presentationBinding
        ) {
            Button("Delete", role: .destructive) {
                guard let deletionRequest = request else {
                    return
                }
                request = nil
                delete(deletionRequest.summaries)
            }
            Button("Cancel", role: .cancel) {
                request = nil
            }
        } message: {
            Text(request?.message ?? "")
        }
    }

    /// Clears the request when the system dismisses the dialog outside the explicit buttons.
    private var presentationBinding: Binding<Bool> {
        Binding {
            request != nil
        } set: { isPresented in
            if !isPresented {
                request = nil
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func notePinSwipeAction(note: NoteSummary, action: @escaping () -> Void) -> some View {
        #if os(iOS)
        swipeActions(edge: .leading) {
            Button(action: action) {
                Label(
                    note.isPinned ? "Unpin" : "Pin",
                    systemImage: note.isPinned ? "pin.slash" : "pin"
                )
            }
            .tint(note.isPinned ? .orange : .accentColor)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func noteDeletionSwipeAction(action: @escaping () -> Void) -> some View {
        #if os(iOS)
        swipeActions(edge: .trailing) {
            // A destructive role makes List begin its own row-removal batch update.
            // Confirmation deliberately defers the model mutation, so retain the red
            // affordance without asking UIKit to remove the row before confirmation.
            Button(action: action) {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        #else
        self
        #endif
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
