import Foundation
import Observation
import UniformTypeIdentifiers

/// Main-actor store that coordinates note persistence, selection, search indexing, and editor saves.
@MainActor
@Observable
final class NotesStore {
    /// The repository is the single source of truth for note and TextBundle mutations.
    @ObservationIgnored
    private var repository: TextBundleNoteRepository
    /// Creates and prepares a repository before a location change becomes visible in the UI.
    @ObservationIgnored
    private let repositoryFactory: (NoteStorageLocation) throws -> TextBundleNoteRepository
    /// Loads summaries from a prepared target repository before it replaces the current state.
    @ObservationIgnored
    private let repositoryNotesLoader: (TextBundleNoteRepository) throws -> [NoteSummary]
    /// Keeps availability checks injectable for storage-setting tests.
    @ObservationIgnored
    private let iCloudAvailability: () -> Bool
    /// Injectable autosave suspension used to make transition races deterministic in tests.
    @ObservationIgnored
    private let autosavePause: @Sendable () async -> Void
    /// Signals completion of deferred work so tests can coordinate cancellation without timing delays.
    @ObservationIgnored
    private let autosaveCompletion: @Sendable () async -> Void
    /// Search is actor-isolated because SQLite access must not run on the main actor.
    @ObservationIgnored
    private let searchIndex: SQLiteNoteSearchIndex
    /// Persists the user's sidebar ordering independently from note storage.
    @ObservationIgnored
    private var sortPreferenceStorage: NoteSortPreferenceStorage
    /// Persists only successful user-initiated storage changes.
    @ObservationIgnored
    private var storagePreferenceStorage: NoteStoragePreferenceStorage

    /// Lightweight rows kept in sidebar order; full note bodies are loaded only for selection.
    var notes: [NoteSummary] = []
    /// Assets belonging to the selected TextBundle, including whether each is linked in the body.
    var attachments: [TextBundleAsset] = []
    /// File size of the selected bundle, used by the attachment inspector.
    var selectedNoteBundleSize: Int64 = 0
    /// Debounced content statistics so inspector rendering does not parse Markdown on each keystroke.
    var selectedNoteStatistics = NoteStatistics(markdown: "")
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
    /// The currently loaded directory, reflected by the Notes Location picker.
    var storageLocation: NoteStorageLocation
    /// Prevents concurrent storage transitions from racing repository state.
    var isChangingStorage = false

    /// Editable in-memory note; this is intentionally separate from the lightweight summary list.
    private var selectedNote: Note?
    /// Debounced save task cancelled whenever selection or an immediate save takes precedence.
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
    /// Cancels stale statistics calculations while the user is still typing.
    @ObservationIgnored
    private var statisticsTask: Task<Void, Never>?
    /// Owns Markdown statistics work independently from text entry and autosave.
    @ObservationIgnored
    private let statisticsWorker = NoteStatisticsWorker()
    /// Owns disk-bound editor writes so the main actor remains available for typing and rendering.
    @ObservationIgnored
    private let autosaveWorker = NoteAutosaveWorker()
    /// Cancellable background synchronization for the SQLite search index.
    @ObservationIgnored
    private var searchIndexTask: Task<Void, Never>?
    /// Monotonic identity for the repository whose state is currently published.
    @ObservationIgnored
    private var repositoryGeneration: UInt64 = 0
    /// Monotonic editor identity used to discard save work superseded by newer typing.
    @ObservationIgnored
    private var editorRevision: UInt64 = 0
    /// Serialises index operations with generation invalidation so old work cannot run after a switch.
    @ObservationIgnored
    private let searchIndexGate = SearchIndexGenerationGate()

    init(
        repository: TextBundleNoteRepository = .production(),
        sortPreferenceStorage: NoteSortPreferenceStorage = .standard,
        searchIndex: SQLiteNoteSearchIndex? = nil,
        storagePreferenceStorage: NoteStoragePreferenceStorage = .standard,
        repositoryFactory: @escaping (NoteStorageLocation) throws -> TextBundleNoteRepository = {
            try TextBundleNoteRepository.repository(for: $0)
        },
        repositoryNotesLoader: @escaping (TextBundleNoteRepository) throws -> [NoteSummary] = {
            try $0.listNotes()
        },
        iCloudAvailability: @escaping () -> Bool = {
            TextBundleNoteRepository.isICloudAvailable()
        },
        autosavePause: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(500))
        },
        autosaveCompletion: @escaping @Sendable () async -> Void = {}
    ) {
        self.repository = repository
        self.repositoryFactory = repositoryFactory
        self.repositoryNotesLoader = repositoryNotesLoader
        self.iCloudAvailability = iCloudAvailability
        self.autosavePause = autosavePause
        self.autosaveCompletion = autosaveCompletion
        self.searchIndex = searchIndex ?? SQLiteNoteSearchIndex.production()
        self.sortPreferenceStorage = sortPreferenceStorage
        self.storagePreferenceStorage = storagePreferenceStorage
        sortPreference = sortPreferenceStorage.preference
        storageLocation = repository.storageLocation
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

    /// Determines whether the iCloud choice can be selected in Settings on this device.
    var isICloudStorageAvailable: Bool {
        iCloudAvailability()
    }

    /// Saves pending edits and then switches to the independent note location.
    func changeStorageLocation(to location: NoteStorageLocation) async {
        guard location != storageLocation, !isChangingStorage else {
            return
        }

        guard location != .iCloud || isICloudStorageAvailable else {
            errorMessage = NoteRepositoryError.storageUnavailable.localizedDescription
            return
        }

        isChangingStorage = true
        isLoading = true
        let previousGeneration = repositoryGeneration
        repositoryGeneration &+= 1
        cancelDeferredWork()
        searchIndexTask?.cancel()
        await searchIndexGate.advance(to: repositoryGeneration)
        defer {
            isChangingStorage = false
            isLoading = false
        }

        do {
            try await saveCurrentNoteIfNeeded(generation: previousGeneration)
            let replacementRepository = try repositoryFactory(location)
            let replacementNotes = try sortPreference.sorted(repositoryNotesLoader(replacementRepository))

            repository = replacementRepository
            storageLocation = location
            selectedNoteID = nil
            clearSelection()
            notes = replacementNotes
            searchStatus = .notReady
            storagePreferenceStorage.location = location
            startSearchIndexSynchronization()
            AppLog.info("Changed note storage to \(replacementRepository.storageDescription)")
        } catch {
            startSearchIndexSynchronization()
            AppLog.error("Failed to change note storage: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Projects current unsaved editor text into the inspector's derived statistics.
    var selectedNoteInfo: NoteInfo? {
        guard let summary = selectedNoteSummary else {
            return nil
        }

        return NoteInfo(
            summary: summary,
            statistics: selectedNoteStatistics,
            location: repository.noteLocationDescription,
            byteCount: selectedNoteBundleSize
        )
    }

    /// Loads sidebar summaries, restores platform-appropriate selection, and starts index sync.
    func loadNotes() async {
        guard canMutateNotes else {
            return
        }
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
        guard canMutateNotes else {
            return
        }
        AppLog.info("Creating note")
        let generation = repositoryGeneration
        do {
            let note = try repository.createNote(initialMarkdown: initialMarkdown)
            try refreshNotes()
            try select(note)
            guard await indexNote(note, generation: generation) else {
                return
            }
            guard isCurrentRepository(generation) else {
                return
            }
            AppLog.info("Created note: \(logName(for: note.url))")
        } catch {
            guard isCurrentRepository(generation) else {
                return
            }
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
        guard canMutateNotes else {
            return
        }
        guard !summaries.isEmpty else {
            AppLog.debug("Ignoring empty delete request")
            return
        }

        AppLog.info("Deleting \(summaries.count) notes")
        let generation = repositoryGeneration
        do {
            cancelDeferredWork()
            await autosaveWorker.finishPendingWrites()
            let nextSelectionID = replacementSelectionID(afterDeleting: summaries)
            for summary in summaries {
                try repository.delete(summary)
                guard await removeFromSearchIndex(noteID: summary.id, generation: generation) else {
                    return
                }
                AppLog.info("Deleted note: \(logName(for: summary.url))")
            }
            guard isCurrentRepository(generation) else {
                return
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
            guard isCurrentRepository(generation) else {
                return
            }
            AppLog.error("Failed to delete notes: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the previous note before loading the newly selected note from storage.
    func selectionChanged() async {
        guard canMutateNotes else {
            return
        }
        guard let selectedNoteID else {
            AppLog.info("Clearing note selection")
            clearSelection()
            return
        }

        AppLog.info("Changing selection to \(logName(for: selectedNoteID))")
        let generation = repositoryGeneration
        do {
            try await saveCurrentNoteIfNeeded(generation: generation)
            guard isCurrentRepository(generation) else {
                return
            }
            try selectNote(id: selectedNoteID)
        } catch {
            guard isCurrentRepository(generation) else {
                return
            }
            AppLog.error("Failed to change selection: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Records a user edit without invalidating selection-dependent views or parsing attachments per keystroke.
    func updateEditorText(_ newText: String) {
        guard canMutateNotes, newText != editorText else {
            return
        }
        editorText = newText
        editorRevision &+= 1
        scheduleStatisticsUpdate(for: newText, revision: editorRevision)
        scheduleSave()
    }

    /// Applies a preview checkbox change through the same Markdown update and deferred-save path as editing.
    func toggleTask(_ marker: MarkdownTaskMarker, to state: MarkdownTaskState) {
        guard canMutateNotes,
              let updatedMarkdown = MarkdownFormatting.togglingTask(
                  in: editorText,
                  marker: marker,
                  to: state
              )
        else {
            return
        }

        updateEditorText(updatedMarkdown)
    }

    /// Flushes pending edits before creating an immutable snapshot for an exporter.
    func exportPayload(for summary: NoteSummary) async throws -> NoteExportPayload {
        guard canMutateNotes else {
            throw NoteRepositoryError.storageUnavailable
        }
        let generation = repositoryGeneration
        try await saveCurrentNoteIfNeeded(generation: generation)
        guard isCurrentRepository(generation) else {
            throw NoteRepositoryError.storageUnavailable
        }
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
        guard canMutateNotes else {
            return nil
        }
        guard var selectedNote else {
            AppLog.debug("Ignoring tag add because no note is selected")
            return nil
        }

        do {
            let generation = repositoryGeneration
            var metadata = selectedNote.metadata
            let inserted = metadata.add(tag)
            try saveSelectedNoteMetadata(metadata, in: &selectedNote)
            Task { [weak self, selectedNote, generation] in
                guard let self, isCurrentRepository(generation) else {
                    return
                }
                _ = await indexNote(selectedNote, generation: generation)
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
        guard canMutateNotes else {
            return
        }
        guard var selectedNote else {
            AppLog.debug("Ignoring tag removal because no note is selected")
            return
        }

        guard selectedNote.metadata.tags.contains(where: { $0.normalizedKey == tag.normalizedKey }) else {
            return
        }

        let generation = repositoryGeneration
        do {
            var metadata = selectedNote.metadata
            metadata.remove(tag)
            try saveSelectedNoteMetadata(metadata, in: &selectedNote)
            guard await indexNote(selectedNote, generation: generation) else {
                return
            }
            guard isCurrentRepository(generation) else {
                return
            }
            AppLog.info("Tag removed; tag=\(tag.name)")
        } catch {
            guard isCurrentRepository(generation) else {
                return
            }
            AppLog.error("Failed to remove tag: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Pins or unpins a note without changing its Markdown content or current selection.
    func togglePin(for summary: NoteSummary) async {
        guard canMutateNotes else {
            return
        }
        let generation = repositoryGeneration
        do {
            try await saveCurrentNoteIfNeeded(generation: generation)
            guard isCurrentRepository(generation) else {
                return
            }
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
            guard isCurrentRepository(generation) else {
                return
            }
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
        guard canMutateNotes else {
            throw NoteRepositoryError.storageUnavailable
        }
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
        guard canMutateNotes else {
            throw NoteRepositoryError.storageUnavailable
        }
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
        guard canMutateNotes else {
            return
        }
        guard let selectedNote else {
            AppLog.debug("Ignoring attachment delete because no note is selected")
            return
        }

        guard attachments.contains(attachment) else {
            AppLog.warning("Ignoring stale attachment delete request")
            return
        }

        AppLog.info("Deleting attachment; name=\(attachment.filename); linked=\(attachment.isLinked)")
        let generation = repositoryGeneration
        cancelDeferredWork()

        do {
            await autosaveWorker.finishPendingWrites()
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
                try await autosaveWorker.save(markdown: updatedNote.markdown, at: updatedNote.url)
                self.selectedNote = updatedNote
                editorText = updatedMarkdown
                guard await indexNote(updatedNote, generation: generation) else {
                    return
                }
                guard isCurrentRepository(generation) else {
                    return
                }
            }

            guard isCurrentRepository(generation) else {
                return
            }
            try repository.deleteAttachment(attachment.url, from: selectedNote.url)
            try refreshNotes()
            try refreshAttachments()
            AppLog.info("Attachment deletion completed; name=\(attachment.filename)")
        } catch {
            guard isCurrentRepository(generation) else {
                return
            }
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
        guard canMutateNotes else {
            return
        }
        AppLog.info("Saving current note immediately")
        saveTask?.cancel()
        let generation = repositoryGeneration
        guard var selectedNote else {
            AppLog.debug("Ignoring save request because no note is selected")
            return
        }

        do {
            selectedNote.markdown = editorText
            try await autosaveWorker.save(markdown: selectedNote.markdown, at: selectedNote.url)
            guard isCurrentRepository(generation) else {
                return
            }
            guard await indexNote(selectedNote, generation: generation) else {
                return
            }
            guard isCurrentRepository(generation) else {
                return
            }
            selectedNoteBundleSize = repository.totalBundleSize(at: selectedNote.url)
            try refreshNotes()
            let assetBaseURL = selectedNote.url.appendingPathComponent(
                TextBundleNoteRepository.assetsFolder,
                isDirectory: true
            )
            applyAttachmentLinkStates(
                linkedURLs: MarkdownAttachmentReferences.linkedURLs(
                    in: selectedNote.markdown,
                    assetBaseURL: assetBaseURL
                )
            )
            AppLog.info("Saved note: \(logName(for: selectedNote.url))")
        } catch {
            guard isCurrentRepository(generation) else {
                return
            }
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
        guard canMutateNotes else {
            return nil
        }
        let generation = repositoryGeneration
        guard searchStatus == .ready else {
            AppLog.debug(
                "Skipping note search because index status is \(String(describing: searchStatus)); "
                    + "queryLength=\(query.count)"
            )
            return nil
        }

        do {
            guard let page = try await searchIndexGate.run(for: generation, operation: {
                try await self.searchIndex.search(query, filter: filter, limit: limit, offset: offset)
            }) else {
                return nil
            }
            guard isCurrentRepository(generation) else {
                return nil
            }
            AppLog.debug(
                "Note search completed; queryLength=\(query.count); "
                    + "filter=\(filter?.rawValue ?? "none"); "
                    + "resultCount=\(page.results.count); hasMore=\(page.hasMore)"
            )
            return page
        } catch {
            guard isCurrentRepository(generation) else {
                return nil
            }
            AppLog.error("Note search failed: \(error.localizedDescription)")
            searchStatus = .unavailable
            return nil
        }
    }

    /// Rebuilds the search index from all current summaries after a user-requested retry.
    func retrySearchIndex() {
        guard canMutateNotes else {
            return
        }
        startSearchIndexSynchronization(rebuild: true)
    }
}

private extension NotesStore {
    /// Commits metadata-only edits and immediately updates every selected-note projection.
    private func saveSelectedNoteMetadata(_ metadata: NoteMetadata, in note: inout Note) throws {
        note.metadata = metadata
        try repository.updateNoteMetadata(metadata, for: note.url)
        selectedNote = note
        selectedNoteTags = metadata.tags
        applyMetadata(metadata, toSummaryFor: note.id)
        selectedNoteBundleSize = repository.totalBundleSize(at: note.url)
    }

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
        selectedNoteStatistics = NoteStatistics(markdown: note.markdown)
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
        selectedNoteStatistics = NoteStatistics(markdown: "")
    }

    /// Rebuilds sidebar summaries from storage and applies the current sort preference.
    private func refreshNotes() throws {
        notes = try sortedNotes()
    }

    /// Applies the current order to an already-loaded summary collection.
    private func applySortedNotes(_ summaries: [NoteSummary]) {
        notes = sortPreference.sorted(summaries)
    }

    /// Replaces only the row affected by a text save, preserving the rest of the loaded library.
    private func applySavedSummary(_ summary: NoteSummary) {
        guard let index = notes.firstIndex(where: { $0.id == summary.id }) else {
            return
        }

        var updatedSummaries = notes
        updatedSummaries[index] = summary
        applySortedNotes(updatedSummaries)
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

    /// Publishes attachment link badges after the deferred save has parsed the final idle text.
    private func applyAttachmentLinkStates(linkedURLs: Set<URL>) {
        guard !attachments.isEmpty else {
            return
        }
        let updatedAttachments = attachments.map { attachment in
            TextBundleAsset(
                url: attachment.url,
                contentType: attachment.contentType,
                isLinked: linkedURLs.contains(attachment.url.notraCanonicalFileURL)
            )
        }
        guard updatedAttachments != attachments else {
            return
        }
        attachments = updatedAttachments
    }

    /// Cancels work whose result would be stale after selection or deletion changes.
    private func cancelDeferredWork() {
        saveTask?.cancel()
        saveTask = nil
        statisticsTask?.cancel()
        statisticsTask = nil
    }

    /// Calculates inspector-only statistics after typing has settled, outside the input callback.
    private func scheduleStatisticsUpdate(for markdown: String, revision: UInt64) {
        statisticsTask?.cancel()
        let worker = statisticsWorker
        statisticsTask = Task { [weak self, worker] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            let statistics = await worker.statistics(for: markdown)
            guard !Task.isCancelled,
                  let self,
                  editorRevision == revision
            else {
                return
            }

            selectedNoteStatistics = statistics
        }
    }

    /// Starts one cancellable index operation and reports completion back on the main actor.
    private func startSearchIndexSynchronization(rebuild: Bool = false) {
        searchIndexTask?.cancel()
        searchStatus = .indexing
        let generation = repositoryGeneration
        let noteIDs = notes.map(\.id)
        AppLog.info(
            "Starting note search index \(rebuild ? "rebuild" : "synchronization"); "
                + "noteCount=\(noteIDs.count)"
        )
        let index = searchIndex
        let gate = searchIndexGate
        searchIndexTask = Task { [weak self, index, gate] in
            do {
                guard try await (gate.run(for: generation) {
                    if rebuild {
                        try await index.rebuild(noteIDs: noteIDs)
                    } else {
                        try await index.synchronize(noteIDs: noteIDs)
                    }
                }) != nil else {
                    return
                }

                guard !Task.isCancelled, let self, isCurrentRepository(generation) else {
                    return
                }
                markSearchIndexReady()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, isCurrentRepository(generation) else {
                    return
                }
                let operation = rebuild ? "rebuild" : "synchronize"
                AppLog.error("Failed to \(operation) note search index: \(error.localizedDescription)")
                markSearchIndexUnavailable()
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
    private func indexNote(
        _ note: Note,
        analysis: MarkdownDocumentAnalysis? = nil,
        generation: UInt64
    ) async -> Bool {
        guard isCurrentRepository(generation) else {
            return false
        }

        let noteID = note.url
        let markdown = note.markdown
        let tags = note.metadata.tags
        do {
            guard try await (searchIndexGate.run(for: generation, operation: {
                try await self.searchIndex.index(
                    noteID: noteID,
                    markdown: markdown,
                    tags: tags,
                    analysis: analysis
                )
            })) != nil else {
                return false
            }
            guard isCurrentRepository(generation) else {
                return false
            }
            AppLog.debug("Indexed changed note: \(logName(for: noteID))")
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrentRepository(generation) else {
                return false
            }
            AppLog.error("Failed to index note \(logName(for: noteID)): \(error.localizedDescription)")
            searchStatus = .unavailable
            return false
        }
    }

    /// Removes one note from the actor-owned index without affecting its TextBundle.
    private func removeFromSearchIndex(noteID: URL, generation: UInt64) async -> Bool {
        guard isCurrentRepository(generation) else {
            return false
        }

        do {
            guard try await (searchIndexGate.run(for: generation, operation: {
                try await self.searchIndex.remove(noteID: noteID)
            })) != nil else {
                return false
            }
            guard isCurrentRepository(generation) else {
                return false
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrentRepository(generation) else {
                return false
            }
            AppLog.error("Failed to remove note from search index: \(error.localizedDescription)")
            searchStatus = .unavailable
            return false
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

    private func saveCurrentNoteIfNeeded(generation: UInt64) async throws {
        saveTask?.cancel()
        guard var selectedNote else {
            return
        }

        selectedNote.markdown = editorText
        try await autosaveWorker.save(markdown: selectedNote.markdown, at: selectedNote.url)
        guard isCurrentRepository(generation) else {
            return
        }
        _ = await indexNote(selectedNote, generation: generation)
        guard isCurrentRepository(generation) else {
            return
        }
        selectedNoteBundleSize = repository.totalBundleSize(at: selectedNote.url)
        AppLog.info("Saved current note before state transition: \(logName(for: selectedNote.url))")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard var noteToSave = selectedNote else {
            return
        }

        noteToSave.markdown = editorText
        let noteName = logName(for: noteToSave.url)
        let noteID = noteToSave.id
        let generation = repositoryGeneration
        let revision = editorRevision
        let repository = repository
        let autosavePause = autosavePause
        let autosaveCompletion = autosaveCompletion
        saveTask = Task { [weak self] in
            defer {
                Task {
                    await autosaveCompletion()
                }
            }
            guard !Task.isCancelled, let self, isCurrentRepository(generation) else {
                return
            }
            await autosavePause()
            guard !Task.isCancelled, isCurrentRepository(generation) else {
                return
            }
            do {
                try await autosaveWorker.save(markdown: noteToSave.markdown, at: noteToSave.url)
                guard !Task.isCancelled,
                      isCurrentRepository(generation),
                      editorRevision == revision,
                      selectedNoteID == noteID
                else {
                    return
                }
                let analysis = MarkdownDocumentAnalysis.analyse(markdown: noteToSave.markdown)
                guard await indexNote(noteToSave, analysis: analysis, generation: generation) else {
                    return
                }
                guard !Task.isCancelled,
                      isCurrentRepository(generation),
                      editorRevision == revision,
                      selectedNoteID == noteID
                else {
                    return
                }
                let savedSummary = try repository.summary(for: noteToSave.url, analysis: analysis)
                applySavedSummary(savedSummary)
                if !attachments.isEmpty {
                    let assetBaseURL = noteToSave.url.appendingPathComponent(
                        TextBundleNoteRepository.assetsFolder,
                        isDirectory: true
                    )
                    applyAttachmentLinkStates(
                        linkedURLs: MarkdownAttachmentReferences.linkedURLs(
                            in: analysis,
                            assetBaseURL: assetBaseURL
                        )
                    )
                }
                AppLog.debug("Autosaved note: \(noteName)")
            } catch {
                guard !Task.isCancelled, isCurrentRepository(generation) else {
                    return
                }
                AppLog.error("Autosave failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func isCurrentRepository(_ generation: UInt64) -> Bool {
        repositoryGeneration == generation
    }

    /// Rejects note commands while the storage transition owns the repository boundary.
    private var canMutateNotes: Bool {
        guard !isChangingStorage else {
            AppLog.debug("Ignoring note command during storage transition")
            return false
        }
        return true
    }

    private func logName(for url: URL?) -> String {
        guard let url else {
            return "none"
        }

        return url.deletingPathExtension().lastPathComponent
    }
}

/// Prevents an old index operation from overlapping the state replacement of a storage switch.
private actor SearchIndexGenerationGate {
    private var generation: UInt64 = 0
    private var activeOperations = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func advance(to generation: UInt64) async {
        self.generation = generation
        guard activeOperations > 0 else {
            return
        }

        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    func run<T: Sendable>(
        for generation: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        guard self.generation == generation else {
            return nil
        }

        activeOperations += 1
        defer {
            activeOperations -= 1
            if activeOperations == 0 {
                let waiters = idleWaiters
                idleWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        return try await operation()
    }
}
