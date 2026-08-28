import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
final class NotesStore {
    @ObservationIgnored
    private let repository: TextBundleNoteRepository
    @ObservationIgnored
    private let searchIndex: any NoteSearchIndex
    @ObservationIgnored
    private var sortPreferenceStorage: NoteSortPreferenceStorage

    var notes: [NoteSummary] = []
    var attachments: [TextBundleAsset] = []
    var selectedNoteBundleSize: Int64 = 0
    var selectedNoteID: URL?
    var editorText = ""
    var isLoading = false
    var errorMessage: String?
    var searchStatus = NoteSearchStatus.notReady
    var sortPreference: NoteSortPreference
    var selectedNoteTags: [NoteTag] = []

    private var selectedNote: Note?
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
    @ObservationIgnored
    private var searchIndexTask: Task<Void, Never>?

    init(
        repository: TextBundleNoteRepository = .production(),
        sortPreferenceStorage: NoteSortPreferenceStorage = .standard,
        searchIndex: (any NoteSearchIndex)? = nil
    ) {
        self.repository = repository
        self.searchIndex = searchIndex ?? SQLiteNoteSearchIndex.production()
        self.sortPreferenceStorage = sortPreferenceStorage
        sortPreference = sortPreferenceStorage.preference
        AppLog.info("Initialized notes store with \(repository.storageDescription)")
    }

    var selectedNoteSummary: NoteSummary? {
        guard let selectedNoteID else {
            return nil
        }

        return notes.first { $0.id == selectedNoteID }
    }

    var selectedNoteURL: URL? {
        selectedNote?.url
    }

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

    func createNote() async {
        AppLog.info("Creating note")
        do {
            let note = try repository.createNote()
            try refreshNotes()
            try select(note)
            await indexNote(note)
            AppLog.info("Created note: \(logName(for: note.url))")
        } catch {
            AppLog.error("Failed to create note: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedNote() async {
        guard let selectedNoteID,
              let summary = notes.first(where: { $0.id == selectedNoteID })
        else {
            return
        }

        await deleteNotes([summary])
    }

    func deleteNotes(at offsets: IndexSet) async {
        let summaries = offsets.map { notes[$0] }
        await deleteNotes(summaries)
    }

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

    func updateEditorText(_ newText: String) {
        editorText = newText
        selectedNote?.markdown = newText
        refreshAttachmentLinkStates()
        scheduleSave()
    }

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
            selectedNoteBundleSize = repository.totalBundleSize(at: selectedNote.url)
            await indexNote(selectedNote)
            AppLog.info("Tag removed; tag=\(tag.name)")
        } catch {
            AppLog.error("Failed to remove tag: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

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

    func applyFormatting(_ command: NoteFormattingCommand) {
        AppLog.info("Applying formatting command: \(command)")
        updateEditorText(MarkdownFormatting.apply(command, to: editorText, selection: nil))
    }

    func applyHeading(level: MarkdownHeadingLevel) {
        AppLog.info("Applying heading level: H\(level.rawValue)")
        updateEditorText(
            MarkdownFormatting.applyHeading(level: level, to: editorText, selection: nil)
        )
    }

    func setSortField(_ field: NoteSortField) {
        guard sortPreference.field != field else {
            return
        }

        sortPreference.field = field
        sortPreferenceStorage.preference = sortPreference
        notes = sortPreference.sorted(notes)
        AppLog.info("Changed sort field to \(field)")
    }

    func setSortDirection(_ direction: NoteSortDirection) {
        guard sortPreference.direction != direction else {
            return
        }

        sortPreference.direction = direction
        sortPreferenceStorage.preference = sortPreference
        notes = sortPreference.sorted(notes)
        AppLog.info("Changed sort direction to \(direction)")
    }

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

    func searchNotes(query: String, limit: Int, offset: Int) async -> NoteSearchPage? {
        guard searchStatus == .ready else {
            AppLog.debug(
                "Skipping note search because index status is \(String(describing: searchStatus)); "
                    + "queryLength=\(query.count)"
            )
            return nil
        }

        do {
            let page = try await searchIndex.search(query, limit: limit, offset: offset)
            AppLog.debug(
                "Note search completed; queryLength=\(query.count); "
                    + "resultCount=\(page.results.count); hasMore=\(page.hasMore)"
            )
            return page
        } catch {
            AppLog.error("Note search failed: \(error.localizedDescription)")
            searchStatus = .unavailable
            return nil
        }
    }

    func retrySearchIndex() {
        startSearchIndexSynchronization(rebuild: true)
    }
}

private extension NotesStore {
    private func selectNote(id: URL) throws {
        let note = try repository.loadNote(at: id)
        try select(note)
        AppLog.info("Selected note: \(logName(for: note.url))")
    }

    private func select(_ note: Note) throws {
        selectedNoteID = note.id
        selectedNote = note
        editorText = note.markdown
        selectedNoteTags = note.metadata.tags
        try refreshAttachments()
    }

    private func clearSelection() {
        selectedNote = nil
        editorText = ""
        attachments = []
        selectedNoteTags = []
        selectedNoteBundleSize = 0
    }

    private func refreshNotes() throws {
        notes = try sortedNotes()
    }

    private func applySortedNotes(_ summaries: [NoteSummary]) {
        notes = sortPreference.sorted(summaries)
    }

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

    private func cancelDeferredWork() {
        saveTask?.cancel()
    }

    private func startSearchIndexSynchronization(rebuild: Bool = false) {
        searchIndexTask?.cancel()
        searchStatus = .indexing
        let noteIDs = notes.map(\.id)
        AppLog.info(
            "Starting note search index \(rebuild ? "rebuild" : "synchronization"); "
                + "noteCount=\(noteIDs.count)"
        )
        let index = searchIndex
        if rebuild {
            searchIndexTask = Task { [weak self, index] in
                do {
                    try await index.rebuild(noteIDs: noteIDs)
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.markSearchIndexReady()
                } catch is CancellationError {
                    return
                } catch {
                    AppLog.error("Failed to rebuild note search index: \(error.localizedDescription)")
                    self?.markSearchIndexUnavailable()
                }
            }
        } else {
            searchIndexTask = Task { [weak self, index] in
                do {
                    try await index.synchronize(noteIDs: noteIDs)
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.markSearchIndexReady()
                } catch is CancellationError {
                    return
                } catch {
                    AppLog.error("Failed to synchronize note search index: \(error.localizedDescription)")
                    self?.markSearchIndexUnavailable()
                }
            }
        }
    }

    private func markSearchIndexReady() {
        searchStatus = .ready
        AppLog.info("Note search index is ready")
    }

    private func markSearchIndexUnavailable() {
        searchStatus = .unavailable
        AppLog.error("Note search index is unavailable")
    }

    private func indexNote(_ note: Note) async {
        do {
            try await searchIndex.index(noteID: note.url, markdown: note.markdown, tags: note.metadata.tags)
            AppLog.debug("Indexed changed note: \(logName(for: note.url))")
        } catch {
            AppLog.error("Failed to index note \(logName(for: note.url)): \(error.localizedDescription)")
            searchStatus = .unavailable
        }
    }

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
                await MainActor.run {
                    self.applySortedNotes(reloadedNotes)
                    self.selectedNoteBundleSize = bundleSize
                }
                AppLog.debug("Autosaved note: \(noteName)")
            } catch {
                AppLog.error("Autosave failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
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
