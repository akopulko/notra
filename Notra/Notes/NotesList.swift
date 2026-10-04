import Combine
import SwiftUI

private struct SearchRequest: Hashable {
    let query: String
    let filter: NoteSearchFilter?
    let status: String
    let matchingBundleNames: Set<String>?
}

/// Owns the searchable, sortable note list, its New Note toolbar action, and context-menu exports.
struct NotesList: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: NotesStore
    let isEditing: Bool
    @Binding var searchText: String
    let createNote: () -> Void
    /// Shared export entry point used by row context menus and scene commands.
    let exportNote: (NoteSummary, NoteExportAction) -> Void
    /// Monotonic scene command event requesting deletion of the current selection.
    let deleteSelectedNoteRequestID: Int
    let selectedTagIDs: Set<String>
    #if os(iOS)
    @Namespace private var settingsZoom
    #endif
    @State private var isSearchPresented = false
    @State private var groupingReferenceDate = Date.now
    @State private var searchFilters: [NoteSearchFilter] = []
    #if os(macOS)
    /// Supplies the macOS search field with selectable prefilter tokens.
    @State private var suggestedSearchFilters = NoteSearchFilter.allCases
    #endif
    @State private var searchResultIDs: [URL] = []
    @State private var searchResultOffset = 0
    @State private var searchGeneration = 0
    @State private var hasMoreSearchResults = false
    @State private var isLoadingMoreSearchResults = false
    @State private var isRefreshingSearchResults = false
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
                    #if os(iOS)
                    SortNotesMenu(
                        preference: store.sortPreference,
                        setField: store.setSortField,
                        setDirection: store.setSortDirection
                    )
                    settingsButton
                    #endif
                }
            }
            .toolbar {
                DefaultToolbarItem(kind: .search, placement: .automatic)
            }

            #if os(iOS)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
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
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                groupingReferenceDate = .now
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    groupingReferenceDate = .now
                }
            }
            .task(id: searchRequest) {
                await refreshSearchResults(for: searchRequest)
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
        let effectiveCalendar = groupingCalendar
        let dateSections = trimmedSearchText.isEmpty
            ? NoteDateGrouping.sections(
                in: groups.notes,
                field: store.sortPreference.field,
                now: groupingReferenceDate,
                calendar: effectiveCalendar
            )
            : []

        return List(selection: $store.selectedNoteID) {
            if !groups.pinned.isEmpty {
                noteSection(
                    title: Text(LocalizedStringResource(
                        "Pinned",
                        comment: "Sidebar section containing pinned notes."
                    ))
                    .foregroundStyle(MarkdownTheme.preferred(for: colorScheme).preview.italic.color),
                    notes: groups.pinned
                )
            }

            if trimmedSearchText.isEmpty {
                ForEach(dateSections) { section in
                    noteSection(
                        title: dateSectionTitle(section, calendar: effectiveCalendar),
                        notes: section.notes
                    )
                }
            } else if !groups.notes.isEmpty {
                noteSection(
                    title: Text(LocalizedStringResource(
                        "Notes",
                        comment: "Sidebar section containing unpinned notes."
                    )),
                    notes: groups.notes
                )
            }

            if isSearching, hasMoreSearchResults {
                loadMoreRow
            }
        }
        .accessibilityIdentifier("notes.content")
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
                } else if groups.pinned.isEmpty, groups.notes.isEmpty {
                    if isSearching || !selectedTagIDs.isEmpty {
                        searchEmptyState
                    }
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
        .onChange(of: deleteSelectedNoteRequestID) {
            guard let summary = store.selectedNoteSummary else {
                return
            }
            requestNoteDeletion([summary])
        }
        .modifier(NoteDeletionConfirmationModifier(request: $pendingDeletion) { summaries in
            Task {
                await store.deleteNotes(summaries)
            }
        })
    }

    @MainActor
    private func refreshSearchResults(for request: SearchRequest) async {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchResultIDs = []
        searchResultOffset = 0
        hasMoreSearchResults = false
        isLoadingMoreSearchResults = false
        isRefreshingSearchResults = false

        guard isSearching, !request.query.isEmpty else { return }
        isRefreshingSearchResults = true
        defer {
            if searchGeneration == generation {
                isRefreshingSearchResults = false
            }
        }

        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, searchGeneration == generation, request == searchRequest else { return }

        guard let batch = await NoteTagFilter.loadSearchBatch(
            offset: 0,
            limit: 50,
            matchingBundleNames: request.matchingBundleNames,
            fetchPage: { offset, limit in
                await store.searchNotes(
                    query: request.query,
                    filter: request.filter,
                    limit: limit,
                    offset: offset
                )
            }
        ) else {
            return
        }
        guard !Task.isCancelled, searchGeneration == generation, request == searchRequest else { return }

        let noteBundleNames = Set(store.notes.map { $0.url.lastPathComponent })
        let mappedResultCount = batch.resultIDs.reduce(into: 0) { count, resultID in
            if noteBundleNames.contains(resultID.lastPathComponent) {
                count += 1
            }
        }
        AppLog.debug(
            "Search UI received results; resultCount=\(batch.resultIDs.count); "
                + "mappedResultCount=\(mappedResultCount); noteCount=\(store.notes.count)"
        )
        searchResultIDs = batch.resultIDs
        searchResultOffset = batch.nextOffset
        hasMoreSearchResults = batch.hasMore
    }

    private func loadMoreSearchResults() {
        guard isSearching, !trimmedSearchText.isEmpty, hasMoreSearchResults, !isLoadingMoreSearchResults else {
            return
        }

        let request = searchRequest
        let generation = searchGeneration
        let offset = searchResultOffset
        Task { @MainActor in
            isLoadingMoreSearchResults = true
            defer {
                if searchGeneration == generation, request == searchRequest {
                    isLoadingMoreSearchResults = false
                }
            }

            guard let batch = await NoteTagFilter.loadSearchBatch(
                offset: offset,
                limit: 50,
                matchingBundleNames: request.matchingBundleNames,
                fetchPage: { pageOffset, limit in
                    await store.searchNotes(
                        query: request.query,
                        filter: request.filter,
                        limit: limit,
                        offset: pageOffset
                    )
                }
            ) else {
                return
            }
            guard !Task.isCancelled, searchGeneration == generation, request == searchRequest else { return }

            searchResultIDs.append(contentsOf: batch.resultIDs)
            searchResultOffset = batch.nextOffset
            hasMoreSearchResults = batch.hasMore
        }
    }

    private var searchPresentation: Binding<Bool> {
        Binding {
            !isEditing && isSearchPresented
        } set: { isPresented in
            isSearchPresented = !isEditing && isPresented
        }
    }

    private var searchRequest: SearchRequest {
        SearchRequest(
            query: trimmedSearchText,
            filter: selectedSearchFilter,
            status: String(describing: store.searchStatus),
            matchingBundleNames: selectedTagIDs.isEmpty
                ? nil
                : Set(store.notes.filter { NoteTagFilter.matches($0, selectedIDs: selectedTagIDs) }
                    .map { $0.url.lastPathComponent })
        )
    }
}

private extension NotesList {
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

    var visibleNoteGroups: (pinned: [NoteSummary], notes: [NoteSummary]) {
        let tagFilteredNotes = store.notes.filter {
            NoteTagFilter.matches($0, selectedIDs: selectedTagIDs)
        }
        if trimmedSearchText.isEmpty {
            let visibleNotes = selectedSearchFilter.map { filter in
                tagFilteredNotes.filter(filter.matches)
            } ?? tagFilteredNotes
            return partition(visibleNotes)
        }

        let notesByBundleName = Dictionary(
            uniqueKeysWithValues: store.notes.map { ($0.url.lastPathComponent, $0) }
        )
        let rankedNotes = searchResultIDs.compactMap { notesByBundleName[$0.lastPathComponent] }
            .filter { NoteTagFilter.matches($0, selectedIDs: selectedTagIDs) }
        return partition(NotePinning.pinnedFirst(rankedNotes))
    }

    /// Partitions the already ordered list in one pass so each section preserves its sort semantics.
    private func partition(_ notes: [NoteSummary]) -> (pinned: [NoteSummary], notes: [NoteSummary]) {
        var pinned: [NoteSummary] = []
        var unpinned: [NoteSummary] = []
        pinned.reserveCapacity(notes.count)
        unpinned.reserveCapacity(notes.count)

        for note in notes {
            if note.isPinned {
                pinned.append(note)
            } else {
                unpinned.append(note)
            }
        }
        return (pinned, unpinned)
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
        if trimmedSearchText.isEmpty {
            ContentUnavailableView {
                Label("No Matching Notes", systemImage: "magnifyingglass")
            } description: {
                Text("Try removing the selected filter.")
            }
        } else if isRefreshingSearchResults {
            ProgressView()
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

    var groupingCalendar: Calendar {
        var calendar = calendar
        calendar.timeZone = timeZone
        return calendar
    }

    func dateSectionTitle(_ section: NoteDateSection, calendar: Calendar) -> Text {
        var style: Date.FormatStyle = section.id.month != nil ? .dateTime.month(.wide) : .dateTime.year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return Text(section.date, format: style)
            .foregroundStyle(MarkdownTheme.preferred(for: colorScheme).preview.headingSecondary.color)
    }

    func noteSection(title: Text, notes: [NoteSummary]) -> some View {
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
            HStack(spacing: 12) {
                title
                    .font(.headline.weight(.semibold))

                VStack {
                    Divider()
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
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
            Button("shareWithEllipsis", systemImage: "square.and.arrow.up") {
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

    var message: LocalizedStringResource {
        "\(summaries.count) notes will be permanently deleted."
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
            if let message = request?.message {
                Text(message)
            }
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
