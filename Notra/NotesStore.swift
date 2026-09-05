import Foundation
import Observation
import UniformTypeIdentifiers

/// Main-actor store that coordinates note persistence, selection, search indexing, and editor saves.
@MainActor
@Observable
final class NotesStore {
    /// The repository is the single source of truth for note and TextBundle mutations.
    @ObservationIgnored
    private let repository: TextBundleNoteRepository
    /// Search is actor-isolated because SQLite access must not run on the main actor.
    @ObservationIgnored
    private let searchIndex: SQLiteNoteSearchIndex
    /// Persists the user's sidebar ordering independently from note storage.
    @ObservationIgnored
    private var sortPreferenceStorage: NoteSortPreferenceStorage

    /// Lightweight rows kept in sidebar order; full note bodies are loaded only for selection.
    var notes: [NoteSummary] = []
    /// Assets belonging to the selected TextBundle, including whether each is linked in the body.
    var attachments: [TextBundleAsset] = []
    /// File size of the selected bundle, used by the attachment inspector.
    var selectedNoteBundleSize: Int64 = 0
    /// Stable URL identity of the note selected by the split view.
    var selectedNoteID: URL?
    /// Current editor text, which may be newer than the last persisted note on disk.
    var editorText = ""
    /// Drives the initial loading indicator while the repository is being read.
    var isLoading = false
    /// Most recent user-facing storage or indexing error.
    var errorMessage: String?
    /// Search-index lifecycle state used to gate sidebar queries.
    var searchStatus = NoteSearchStatus.notReady
    /// Current field and direction used to order `notes`.
    var sortPreference: NoteSortPreference
    /// Normalized tags from the selected note, kept separate for tag controls.
    var selectedNoteTags: [NoteTag] = []

    /// Editable in-memory note; this is intentionally separate from the lightweight summary list.
    private var selectedNote: Note?
    /// Debounced save task cancelled whenever selection or an immediate save takes precedence.
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
    /// Cancellable background synchronization for the SQLite search index.
    @ObservationIgnored
    private var searchIndexTask: Task<Void, Never>?

    init(
        repository: TextBundleNoteRepository = .production(),
        sortPreferenceStorage: NoteSortPreferenceStorage = .standard,
        searchIndex: SQLiteNoteSearchIndex? = nil
    ) {
        self.repository = repository
        self.searchIndex = searchIndex ?? SQLiteNoteSearchIndex.production()
        self.sortPreferenceStorage = sortPreferenceStorage
        sortPreference = sortPreferenceStorage.preference
        AppLog.info("Initialized notes store with \(repository.storageDescription)")
    }

    /// Finds the list row corresponding to the selected URL after sorting or refreshes.
    var selectedNoteSummary: NoteSummary? {
        guard let selectedNoteID else {
            return nil
        }

        return notes.first { $0.id == selectedNoteID }
    }

    /// Exposes the selected bundle URL without leaking the full editable note.
    var selectedNoteURL: URL? {
        selectedNote?.url
    }

    /// Convenience flag used to enable editor and attachment actions.
    var hasSelection: Bool {
        selectedNote != nil
    }

    var storageDescription: String {
        repository.storageDescription
    }

    var isUsingICloud: Bool {
        repository.isUsingICloud
    }

    var storagePath: String {
        repository.rootURL.path
    }

    /// Projects current unsaved editor text into the inspector's derived statistics.
    var selectedNoteInfo: NoteInfo? {
        guard let summary = selectedNoteSummary else {
            return nil
        }

        return NoteInfo(
            summary: summary,
            markdown: editorText,
            location: repository.noteLocationDescription,
            byteCount: selectedNoteBundleSize
        )
    }

    /// Loads sidebar summaries, restores platform-appropriate selection, and starts index sync.
    func loadNotes() async {
        AppLog.info("Loading notes from \(repository.storageDescription)")
        isLoading = true
        defer { isLoading = false }

        do {
            try refreshNotes()
            #if os(macOS)
            if selectedNoteID == nil {
                selectedNoteID = notes.first?.id
            }
            #endif
            if let selectedNoteID {
                try selectNote(id: selectedNoteID)
            }
            startSearchIndexSynchronization()
            AppLog.info("Loaded \(notes.count) notes; selected note: \(logName(for: selectedNoteID))")
        } catch {
            AppLog.error("Failed to load notes: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Creates, selects, and immediately indexes a new TextBundle with the requested starting content.
    func createNote(initialMarkdown: String = "") async {
        AppLog.info("Creating note")
        do {
            let note = try repository.createNote(initialMarkdown: initialMarkdown)
            try refreshNotes()
            try select(note)
            await indexNote(note)
            AppLog.info("Created note: \(logName(for: note.url))")
        } catch {
            AppLog.error("Failed to create note: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the selected row through the same multi-note path used by context menus.
    func deleteSelectedNote() async {
        guard let selectedNoteID,
              let summary = notes.first(where: { $0.id == selectedNoteID })
        else {
            return
        }

        await deleteNotes([summary])
    }

    /// Converts list offsets to stable summaries before the list can change during deletion.
    func deleteNotes(at offsets: IndexSet) async {
        let summaries = offsets.map { notes[$0] }
        await deleteNotes(summaries)
    }

    /// Deletes summaries, repairs selection, and removes their search entries.
    func deleteNotes(_ summaries: [NoteSummary]) async {
        guard !summaries.isEmpty else {
            AppLog.debug("Ignoring empty delete request")
            return
        }

        AppLog.info("Deleting \(summaries.count) notes")
        do {
            cancelDeferredWork()
            let nextSelectionID = replacementSelectionID(afterDeleting: summaries)
            for summary in summaries {
                try repository.delete(summary)
                await removeFromSearchIndex(noteID: summary.id)
                AppLog.info("Deleted note: \(logName(for: summary.url))")
            }
            try refreshNotes()
            if let selectedNote, summaries.contains(where: { $0.id == selectedNote.id }) {
                selectedNoteID = nextSelectionID
            }
            if let nextID = selectedNoteID {
                try selectNote(id: nextID)
            } else {
                clearSelection()
            }
            AppLog.info("Delete completed; remaining notes: \(notes.count)")
        } catch {
            AppLog.error("Failed to delete notes: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the previous note before loading the newly selected note from storage.
    func selectionChanged() async {
        guard let selectedNoteID else {
            AppLog.info("Clearing note selection")
            clearSelection()
            return
        }

        AppLog.info("Changing selection to \(logName(for: selectedNoteID))")
        do {
            try await saveCurrentNoteIfNeeded()
            try selectNote(id: selectedNoteID)
        } catch {
            AppLog.error("Failed to change selection: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Updates the in-memory note, attachment link badges, and deferred persistence state.
    func updateEditorText(_ newText: String) {
        editorText = newText
        selectedNote?.markdown = newText
        refreshAttachmentLinkStates()
        scheduleSave()
    }

    /// Flushes pending edits before creating an immutable snapshot for an exporter.
    func exportPayload(for summary: NoteSummary) async throws -> NoteExportPayload {
        try await saveCurrentNoteIfNeeded()
        let note = try repository.loadNote(at: summary.url)
        return NoteExportPayload(
            markdown: note.markdown,
            noteURL: note.url,
            suggestedFilename: summary.url.lastPathComponent
        )
    }
}

extension NotesStore {
    /// Persists a normalized tag and updates the selected note's index entry.
    func addTag(_ tag: NoteTag) -> NoteTagMutationResult? {
        guard var selectedNote else {
            AppLog.debug("Ignoring tag add because no note is selected")
            return nil
        }

        do {
            var metadata = selectedNote.metadata
            let inserted = metadata.add(tag)
            selectedNote.metadata = metadata
            try repository.updateNoteMetadata(metadata, for: selectedNote.url)
            self.selectedNote = selectedNote
            selectedNoteTags = metadata.tags
            applyMetadata(metadata, toSummaryFor: selectedNote.id)
            selectedNoteBundleSize = repository.totalBundleSize(at: selectedNote.url)
            Task {
                await indexNote(selectedNote)
            }
            AppLog.info("Tag \(inserted ? "added" : "already exists"); tag=\(tag.name)")
            return inserted ? .added(tag) : .duplicate(tag)
        } catch {
            AppLog.error("Failed to add tag: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Removes a matching tag from metadata, storage, the inspector, and search index.
    func removeTag(_ tag: NoteTag) async {
        guard var selectedNote else {
            AppLog.debug("Ignoring tag removal because no note is selected")
            return
        }

        guard selectedNote.metadata.tags.contains(where: { $0.normalizedKey == tag.normalizedKey }) else {
            return
        }

        do {
            var metadata = selectedNote.metadata
            metadata.remove(tag)
            selectedNote.metadata = metadata
            try repository.updateNoteMetadata(metadata, for: selectedNote.url)
            self.selectedNote = selectedNote
            selectedNoteTags = metadata.tags
            applyMetadata(metadata, toSummaryFor: selectedNote.id)
            selectedNoteBundleSize = repository.totalBundleSize(at: selectedNote.url)
            await indexNote(selectedNote)
            AppLog.info("Tag removed; tag=\(tag.name)")
        } catch {
            AppLog.error("Failed to remove tag: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Pins or unpins a note without changing its Markdown content or current selection.
    func togglePin(for summary: NoteSummary) async {
        do {
            try await saveCurrentNoteIfNeeded()
            var note = try repository.loadNote(at: summary.url)
            if note.metadata.pinnedAt == nil, notes.filter(\.isPinned).count >= NotePinning.maximumPinnedNotes {
                errorMessage = "You can pin up to \(NotePinning.maximumPinnedNotes) notes."
                return
            }

            note.metadata.pinnedAt = note.metadata.pinnedAt == nil ? Date() : nil
            try repository.updateNoteMetadata(note.metadata, for: note.url)

            if selectedNoteID == note.id {
                selectedNote = note
                selectedNoteTags = note.metadata.tags
            }
            try refreshNotes()
            AppLog.info("Note pin state changed: \(logName(for: note.url))")
        } catch {
            AppLog.error("Failed to update note pin: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Encodes image data as a TextBundle asset after enforcing the configured byte limit.
    func importImage(
        data: Data,
        originalFilename: String = "image",
        maximumByteCount: Int64? = nil
    ) throws -> ImportedTextBundleAsset {
        guard let selectedNote else {
            AppLog.warning("Ignoring image import because no note is selected")
            throw NoteRepositoryError.noteNotFound
        }

        if let maximumByteCount, Int64(data.count) > maximumByteCount {
            throw NoteRepositoryError.attachmentTooLarge(
                filename: originalFilename,
                byteCount: Int64(data.count),
                limit: maximumByteCount
            )
        }

        AppLog.info(
            """
            Importing image into selected note; \
            note=\(logName(for: selectedNote.url)); bytes=\(data.count)
            """
        )
        let importedAsset = try repository.importImage(
            data: data,
            originalFilename: originalFilename,
            into: selectedNote.url
        )
        try refreshAttachments()
        AppLog.info("Imported image into selected note; source=\(importedAsset.source)")
        return importedAsset
    }

    /// Copies an external file into the selected bundle after enforcing its byte limit.
    func importAttachment(
        from url: URL,
        maximumByteCount: Int64
    ) throws -> ImportedTextBundleAsset {
        guard let selectedNote else {
            AppLog.warning("Ignoring attachment import because no note is selected")
            throw NoteRepositoryError.noteNotFound
        }

        AppLog.info(
            """
            Importing attachment into selected note; note=\(logName(for: selectedNote.url)); \
            name=\(url.lastPathComponent); limit=\(maximumByteCount)
            """
        )
        let importedAsset = try repository.importAttachment(
            from: url,
            into: selectedNote.url,
            maximumByteCount: maximumByteCount
        )
        try refreshAttachments()
        AppLog.info("Imported attachment into selected note; source=\(importedAsset.source)")
        return importedAsset
    }

    /// Removes an asset and, when linked, removes its Markdown references first.
    func deleteAttachment(_ attachment: TextBundleAsset) async {
        guard let selectedNote else {
            AppLog.debug("Ignoring attachment delete because no note is selected")
            return
        }

        guard attachments.contains(attachment) else {
            AppLog.warning("Ignoring stale attachment delete request")
            return
        }

        AppLog.info("Deleting attachment; name=\(attachment.filename); linked=\(attachment.isLinked)")
        cancelDeferredWork()

        do {
            var updatedNote = selectedNote
            if attachment.isLinked {
                let assetBaseURL = selectedNote.url.appendingPathComponent(
                    TextBundleNoteRepository.assetsFolder,
                    isDirectory: true
                )
                let updatedMarkdown = MarkdownAttachmentReferences.removingReferences(
                    to: attachment.url,
                    from: editorText,
                    assetBaseURL: assetBaseURL
                )
                updatedNote.markdown = updatedMarkdown
                try repository.save(updatedNote)
                self.selectedNote = updatedNote
                editorText = updatedMarkdown
                await indexNote(updatedNote)
            }

            try repository.deleteAttachment(attachment.url, from: selectedNote.url)
            try refreshNotes()
            try refreshAttachments()
            AppLog.info("Attachment deletion completed; name=\(attachment.filename)")
        } catch {
            do {
                try refreshAttachments()
            } catch {
                AppLog.error("Failed to refresh attachments after deletion error: \(error.localizedDescription)")
            }
            AppLog.error("Failed to delete attachment: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Applies a toolbar command to the current editor text and schedules persistence.
    func applyFormatting(_ command: NoteFormattingCommand) {
        AppLog.info("Applying formatting command: \(command)")
        updateEditorText(MarkdownFormatting.apply(command, to: editorText, selection: nil))
    }

    /// Applies a specific heading level while preserving the editor's current text contract.
    func applyHeading(level: MarkdownHeadingLevel) {
        AppLog.info("Applying heading level: H\(level.rawValue)")
        updateEditorText(
            MarkdownFormatting.applyHeading(level: level, to: editorText, selection: nil)
        )
    }

    /// Persists and reorders notes when the sidebar field changes.
    func setSortField(_ field: NoteSortField) {
        guard sortPreference.field != field else {
            return
        }

        sortPreference.field = field
        sortPreferenceStorage.preference = sortPreference
        notes = sortPreference.sorted(notes)
        AppLog.info("Changed sort field to \(field)")
    }

    /// Persists and reorders notes when the sidebar direction changes.
    func setSortDirection(_ direction: NoteSortDirection) {
        guard sortPreference.direction != direction else {
            return
        }

        sortPreference.direction = direction
        sortPreferenceStorage.preference = sortPreference
        notes = sortPreference.sorted(notes)
        AppLog.info("Changed sort direction to \(direction)")
    }

    /// Cancels a deferred save and writes the current note before an explicit lifecycle boundary.
    func saveNow() async {
        AppLog.info("Saving current note immediately")
        saveTask?.cancel()
        guard let selectedNote else {
            AppLog.debug("Ignoring save request because no note is selected")
            return
        }

        do {
            try repository.save(selectedNote)
            await indexNote(selectedNote)
            selectedNoteBundleSize = repository.totalBundleSize(at: selectedNote.url)
            try refreshNotes()
            AppLog.info("Saved note: \(logName(for: selectedNote.url))")
        } catch {
            AppLog.error("Failed to save note: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Queries the ready search index and marks it unavailable when the actor reports failure.
    func searchNotes(
        query: String,
        filter: NoteSearchFilter? = nil,
        limit: Int,
        offset: Int
    ) async -> NoteSearchPage? {
        guard searchStatus == .ready else {
            AppLog.debug(
                "Skipping note search because index status is \(String(describing: searchStatus)); "
                    + "queryLength=\(query.count)"
            )
            return nil
        }

        do {
            let page = try await searchIndex.search(query, filter: filter, limit: limit, offset: offset)
            AppLog.debug(
                "Note search completed; queryLength=\(query.count); "
                    + "filter=\(filter?.rawValue ?? "none"); "
                    + "resultCount=\(page.results.count); hasMore=\(page.hasMore)"
            )
            return page
        } catch {
            AppLog.error("Note search failed: \(error.localizedDescription)")
            searchStatus = .unavailable
            return nil
        }
    }

    /// Rebuilds the search index from all current summaries after a user-requested retry.
    func retrySearchIndex() {
        startSearchIndexSynchronization(rebuild: true)
    }
}

private extension NotesStore {
    /// Loads a note by stable URL, then refreshes all selected-note projections.
    private func selectNote(id: URL) throws {
        let note = try repository.loadNote(at: id)
        try select(note)
        AppLog.info("Selected note: \(logName(for: note.url))")
    }

    /// Copies note content into the editor-facing state and refreshes its attachment list.
    private func select(_ note: Note) throws {
        selectedNoteID = note.id
        selectedNote = note
        editorText = note.markdown
        selectedNoteTags = note.metadata.tags
        try refreshAttachments()
    }

    /// Clears every selected-note projection so stale editor or attachment state cannot remain visible.
    private func clearSelection() {
        selectedNote = nil
        editorText = ""
        attachments = []
        selectedNoteTags = []
        selectedNoteBundleSize = 0
    }

    /// Rebuilds sidebar summaries from storage and applies the current sort preference.
    private func refreshNotes() throws {
        notes = try sortedNotes()
    }

    /// Applies the current order to an already-loaded summary collection.
    private func applySortedNotes(_ summaries: [NoteSummary]) {
        notes = sortPreference.sorted(summaries)
    }

    /// Refreshes row-visible metadata immediately after a metadata-only note update.
    private func applyMetadata(_ metadata: NoteMetadata, toSummaryFor noteID: URL) {
        let updatedSummaries = notes.map { summary in
            guard summary.id == noteID else {
                return summary
            }

            return NoteSummary(
                url: summary.url,
                previewText: summary.previewText,
                previewFirstLineIsHeading: summary.previewFirstLineIsHeading,
                tags: metadata.tags,
                attachmentSummary: summary.attachmentSummary,
                createdAt: summary.createdAt,
                modifiedAt: summary.modifiedAt,
                pinnedAt: metadata.pinnedAt
            )
        }
        applySortedNotes(updatedSummaries)
    }

    /// Reconciles on-disk assets with links in the current, possibly unsaved editor text.
    private func refreshAttachments() throws {
        guard let selectedNote else {
            attachments = []
            selectedNoteBundleSize = 0
            return
        }

        let urls = try repository.assetURLs(in: selectedNote.url)
        let assetBaseURL = selectedNote.url.appendingPathComponent(
            TextBundleNoteRepository.assetsFolder,
            isDirectory: true
        )
        let linkedURLs = MarkdownAttachmentReferences.linkedURLs(
            in: editorText,
            assetBaseURL: assetBaseURL
        )
        attachments = try urls.map { url in
            let contentType = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
                ?? UTType(filenameExtension: url.pathExtension)
            return TextBundleAsset(
                url: url,
                contentType: contentType,
                isLinked: linkedURLs.contains(url.notraCanonicalFileURL)
            )
        }
        selectedNoteBundleSize = repository.totalBundleSize(at: selectedNote.url)
    }

    /// Recomputes only attachment link badges after an editor text change.
    private func refreshAttachmentLinkStates() {
        guard let selectedNote, !attachments.isEmpty else {
            return
        }

        let assetBaseURL = selectedNote.url.appendingPathComponent(
            TextBundleNoteRepository.assetsFolder,
            isDirectory: true
        )
        let linkedURLs = MarkdownAttachmentReferences.linkedURLs(
            in: editorText,
            assetBaseURL: assetBaseURL
        )
        attachments = attachments.map { attachment in
            TextBundleAsset(
                url: attachment.url,
                contentType: attachment.contentType,
                isLinked: linkedURLs.contains(attachment.url.notraCanonicalFileURL)
            )
        }
    }

    /// Cancels work whose result would be stale after selection or deletion changes.
    private func cancelDeferredWork() {
        saveTask?.cancel()
    }

    /// Starts one cancellable index operation and reports completion back on the main actor.
    private func startSearchIndexSynchronization(rebuild: Bool = false) {
        searchIndexTask?.cancel()
        searchStatus = .indexing
        let noteIDs = notes.map(\.id)
        AppLog.info(
            "Starting note search index \(rebuild ? "rebuild" : "synchronization"); "
                + "noteCount=\(noteIDs.count)"
        )
        let index = searchIndex
        searchIndexTask = Task { [weak self, index] in
            do {
                if rebuild {
                    try await index.rebuild(noteIDs: noteIDs)
                } else {
                    try await index.synchronize(noteIDs: noteIDs)
                }

                guard !Task.isCancelled else {
                    return
                }
                self?.markSearchIndexReady()
            } catch is CancellationError {
                return
            } catch {
                let operation = rebuild ? "rebuild" : "synchronize"
                AppLog.error("Failed to \(operation) note search index: \(error.localizedDescription)")
                self?.markSearchIndexUnavailable()
            }
        }
    }

    /// Publishes the state that allows the sidebar to send search requests.
    private func markSearchIndexReady() {
        searchStatus = .ready
        AppLog.info("Note search index is ready")
    }

    /// Publishes the state that prevents failed index requests from repeating indefinitely.
    private func markSearchIndexUnavailable() {
        searchStatus = .unavailable
        AppLog.error("Note search index is unavailable")
    }

    /// Upserts one note's Markdown and tags into the actor-owned full-text index.
    private func indexNote(_ note: Note) async {
        do {
            try await searchIndex.index(noteID: note.url, markdown: note.markdown, tags: note.metadata.tags)
            AppLog.debug("Indexed changed note: \(logName(for: note.url))")
        } catch {
            AppLog.error("Failed to index note \(logName(for: note.url)): \(error.localizedDescription)")
            searchStatus = .unavailable
        }
    }

    /// Removes one note from the actor-owned index without affecting its TextBundle.
    private func removeFromSearchIndex(noteID: URL) async {
        do {
            try await searchIndex.remove(noteID: noteID)
        } catch {
            AppLog.error("Failed to remove note from search index: \(error.localizedDescription)")
            searchStatus = .unavailable
        }
    }

    private func sortedNotes() throws -> [NoteSummary] {
        try sortPreference.sorted(repository.listNotes())
    }

    private func replacementSelectionID(afterDeleting summaries: [NoteSummary]) -> URL? {
        guard let selectedNoteID,
              summaries.contains(where: { $0.id == selectedNoteID }),
              let selectedIndex = notes.firstIndex(where: { $0.id == selectedNoteID })
        else {
            return selectedNoteID
        }

        let deletedIDs = Set(summaries.map(\.id))
        if let previousNote = notes[..<selectedIndex].last(where: { !deletedIDs.contains($0.id) }) {
            return previousNote.id
        }
        if let nextNote = notes.dropFirst(selectedIndex + 1).first(where: { !deletedIDs.contains($0.id) }) {
            return nextNote.id
        }

        return nil
    }

    private func saveCurrentNoteIfNeeded() async throws {
        saveTask?.cancel()
        guard var selectedNote else {
            return
        }

        selectedNote.markdown = editorText
        try repository.save(selectedNote)
        await indexNote(selectedNote)
        selectedNoteBundleSize = repository.totalBundleSize(at: selectedNote.url)
        AppLog.info("Saved current note before state transition: \(logName(for: selectedNote.url))")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard let selectedNote else {
            return
        }

        let noteName = logName(for: selectedNote.url)
        let index = searchIndex
        saveTask = Task { [repository, noteName, index] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            do {
                try repository.save(selectedNote)
                try await index.index(
                    noteID: selectedNote.url,
                    markdown: selectedNote.markdown,
                    tags: selectedNote.metadata.tags
                )
                let bundleSize = repository.totalBundleSize(at: selectedNote.url)
                let reloadedNotes = try repository.listNotes()
                self.applySortedNotes(reloadedNotes)
                self.selectedNoteBundleSize = bundleSize
                AppLog.debug("Autosaved note: \(noteName)")
            } catch {
                AppLog.error("Autosave failed: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func logName(for url: URL?) -> String {
        guard let url else {
            return "none"
        }

        return url.deletingPathExtension().lastPathComponent
    }
}
