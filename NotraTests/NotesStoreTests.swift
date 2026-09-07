import Foundation
@testable import Notra
import Testing

/// Exercises store selection, saving, deletion, import, and search synchronization behavior.
@MainActor
struct NotesStoreTests {
    @Test
    func `deleting selected note selects previous note`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let alpha = try harness.makeNote(markdown: "Alpha")
        try await Task.sleep(for: .milliseconds(50))
        let beta = try harness.makeNote(markdown: "Beta")
        try await Task.sleep(for: .milliseconds(50))
        _ = try harness.makeNote(markdown: "Gamma")

        await harness.store.loadNotes()
        harness.store.selectedNoteID = beta.id
        await harness.store.selectionChanged()

        let betaSummary = try #require(harness.store.notes.first { $0.id == beta.id })
        await harness.store.deleteNotes([betaSummary])

        #expect(harness.store.selectedNoteID == alpha.id)
    }

    @Test
    func `deleting first selected note selects next note`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let alpha = try harness.makeNote(markdown: "Alpha")
        try await Task.sleep(for: .milliseconds(50))
        let beta = try harness.makeNote(markdown: "Beta")

        await harness.store.loadNotes()
        harness.store.selectedNoteID = alpha.id
        await harness.store.selectionChanged()

        let alphaSummary = try #require(harness.store.notes.first { $0.id == alpha.id })
        await harness.store.deleteNotes([alphaSummary])

        #expect(harness.store.selectedNoteID == beta.id)
    }

    @Test
    func `autosave refreshes note order`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }

        let alpha = try harness.makeNote(markdown: "Alpha")
        try await Task.sleep(for: .milliseconds(50))
        let beta = try harness.makeNote(markdown: "Beta")

        await harness.store.loadNotes()
        harness.store.setSortField(.dateEdited)
        harness.store.setSortDirection(.latestFirst)
        harness.store.selectedNoteID = alpha.id
        await harness.store.selectionChanged()
        #expect(harness.store.notes.first?.id == beta.id)

        harness.store.updateEditorText("# Edited")

        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(100))
            if harness.store.notes.first?.id == alpha.id {
                break
            }
        }

        #expect(harness.store.notes.first?.id == alpha.id)
        #expect(harness.store.notes.first?.previewText == "Edited")
    }

    @Test
    func `content search finds body beyond preview line`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }

        let note = try harness.makeNote(markdown: "Visible preview\n\nNeedle in body")

        await harness.store.loadNotes()
        for _ in 0..<50 {
            if harness.store.searchStatus == .ready {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let page = try #require(
            await harness.store.searchNotes(query: "needle body", limit: 50, offset: 0)
        )
        #expect(page.results.map(\.noteID) == [note.url.standardizedFileURL])
    }

    @Test
    func `deleting only selected note clears editor state`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let alpha = try harness.makeNote(markdown: "Alpha")

        await harness.store.loadNotes()
        harness.store.selectedNoteID = alpha.id
        await harness.store.selectionChanged()
        let alphaSummary = try #require(harness.store.notes.first { $0.id == alpha.id })

        await harness.store.deleteNotes([alphaSummary])

        #expect(harness.store.selectedNoteID == nil)
        #expect(!harness.store.hasSelection)
        #expect(harness.store.editorText.isEmpty)
    }

    @Test
    func `creating note uses initial markdown`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }

        await harness.store.createNote(initialMarkdown: "# ")

        #expect(harness.store.hasSelection)
        #expect(harness.store.editorText == "# ")
        #expect(harness.store.notes.first?.previewText == "#")
    }

    @Test
    func `changing storage saves edits and isolates search results`() async throws {
        let localRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let iCloudRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: localRootURL)
            try? FileManager.default.removeItem(at: iCloudRootURL)
        }

        let localRepository = TextBundleNoteRepository(rootURL: localRootURL)
        let iCloudRepository = TextBundleNoteRepository(rootURL: iCloudRootURL, isUsingICloud: true)
        try localRepository.prepareStorage()
        try iCloudRepository.prepareStorage()
        let localNote = try localRepository.createNote(initialMarkdown: "Local note")
        let iCloudNote = try iCloudRepository.createNote(initialMarkdown: "iCloud note")

        let suiteName = "Notra.NotesStoreStorageTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let store = NotesStore(
            repository: localRepository,
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: userDefaults),
            searchIndex: SQLiteNoteSearchIndex(
                databaseURL: localRootURL.appendingPathComponent("search.sqlite")
            ),
            storagePreferenceStorage: NoteStoragePreferenceStorage(userDefaults: userDefaults),
            repositoryFactory: { location in
                switch location {
                case .iCloud:
                    iCloudRepository
                case .localStore:
                    localRepository
                }
            },
            iCloudAvailability: { true }
        )

        await store.loadNotes()
        store.selectedNoteID = localNote.id
        await store.selectionChanged()
        store.updateEditorText("Saved local note")

        await store.changeStorageLocation(to: .iCloud)

        #expect(try localRepository.loadNote(at: localNote.url).markdown == "Saved local note")
        #expect(store.notes.map(\.id) == [iCloudNote.id])
        #expect(store.selectedNoteID == nil)
        #expect(store.storageLocation == .iCloud)
        #expect(NoteStoragePreferenceStorage(userDefaults: userDefaults).location == .iCloud)

        for _ in 0..<50 {
            if store.searchStatus == .ready {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let oldLocationResults = try #require(
            await store.searchNotes(query: "Saved local", limit: 50, offset: 0)
        )
        let newLocationResults = try #require(
            await store.searchNotes(query: "iCloud", limit: 50, offset: 0)
        )
        #expect(oldLocationResults.results.isEmpty)
        #expect(newLocationResults.results.map(\.noteID) == [iCloudNote.url.standardizedFileURL])
    }

    @Test
    func `failed storage change retains state and does not persist preference`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "Existing note")
        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        await harness.store.changeStorageLocation(to: .iCloud)

        #expect(harness.store.storageLocation == .localStore)
        #expect(harness.store.selectedNoteID == note.id)
        #expect(harness.store.notes.map(\.id) == [note.id])
        #expect(NoteStoragePreferenceStorage(userDefaults: harness.userDefaults).location == nil)
    }

    @Test
    func `failed storage factory retains state and does not persist preference`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "Existing note")
        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        let store = NotesStore(
            repository: harness.repository,
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: harness.userDefaults),
            searchIndex: SQLiteNoteSearchIndex(
                databaseURL: harness.repository.rootURL.appendingPathComponent("factory-search.sqlite")
            ),
            storagePreferenceStorage: NoteStoragePreferenceStorage(userDefaults: harness.userDefaults),
            repositoryFactory: { _ in
                throw NoteRepositoryError.storageUnavailable
            },
            iCloudAvailability: { true }
        )
        await store.loadNotes()
        store.selectedNoteID = note.id
        await store.selectionChanged()

        await store.changeStorageLocation(to: .iCloud)

        #expect(store.storageLocation == .localStore)
        #expect(store.selectedNoteID == note.id)
        #expect(store.notes.map(\.id) == [note.id])
        #expect(NoteStoragePreferenceStorage(userDefaults: harness.userDefaults).location == nil)
    }

    @Test
    func `failed storage listing retains state and does not persist preference`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "Existing note")
        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        let iCloudRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: iCloudRootURL)
        }
        let iCloudRepository = TextBundleNoteRepository(rootURL: iCloudRootURL, isUsingICloud: true)
        try iCloudRepository.prepareStorage()
        let store = NotesStore(
            repository: harness.repository,
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: harness.userDefaults),
            searchIndex: SQLiteNoteSearchIndex(
                databaseURL: harness.repository.rootURL.appendingPathComponent("listing-search.sqlite")
            ),
            storagePreferenceStorage: NoteStoragePreferenceStorage(userDefaults: harness.userDefaults),
            repositoryFactory: { _ in iCloudRepository },
            repositoryNotesLoader: { _ in
                throw NoteRepositoryError.storageUnavailable
            },
            iCloudAvailability: { true }
        )
        await store.loadNotes()
        store.selectedNoteID = note.id
        await store.selectionChanged()

        await store.changeStorageLocation(to: .iCloud)

        #expect(store.storageLocation == .localStore)
        #expect(store.selectedNoteID == note.id)
        #expect(store.notes.map(\.id) == [note.id])
        #expect(NoteStoragePreferenceStorage(userDefaults: harness.userDefaults).location == nil)
    }

    @Test
    func `stale autosave cannot overwrite successfully switched storage`() async throws {
        let localRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let iCloudRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: localRootURL)
            try? FileManager.default.removeItem(at: iCloudRootURL)
        }

        let localRepository = TextBundleNoteRepository(rootURL: localRootURL)
        let iCloudRepository = TextBundleNoteRepository(rootURL: iCloudRootURL, isUsingICloud: true)
        try localRepository.prepareStorage()
        try iCloudRepository.prepareStorage()
        let localNote = try localRepository.createNote(initialMarkdown: "Local note")
        let iCloudNote = try iCloudRepository.createNote(initialMarkdown: "iCloud note")
        let autosaveGate = AutosavePauseGate()
        let suiteName = "Notra.NotesStoreAutosaveRaceTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let store = NotesStore(
            repository: localRepository,
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: userDefaults),
            searchIndex: SQLiteNoteSearchIndex(
                databaseURL: localRootURL.appendingPathComponent("search.sqlite")
            ),
            storagePreferenceStorage: NoteStoragePreferenceStorage(userDefaults: userDefaults),
            repositoryFactory: { location in
                switch location {
                case .iCloud:
                    iCloudRepository
                case .localStore:
                    localRepository
                }
            },
            iCloudAvailability: { true },
            autosavePause: {
                await autosaveGate.pause()
            },
            autosaveCompletion: {
                await autosaveGate.markCompleted()
            }
        )

        await store.loadNotes()
        store.selectedNoteID = localNote.id
        await store.selectionChanged()
        store.updateEditorText("Old repository edit")
        await autosaveGate.waitUntilEntered()

        await store.changeStorageLocation(to: .iCloud)

        #expect(store.storageLocation == .iCloud)
        #expect(store.notes.map(\.id) == [iCloudNote.id])
        #expect(store.selectedNoteID == nil)
        #expect(try iCloudRepository.loadNote(at: iCloudNote.url).markdown == "iCloud note")

        await autosaveGate.release()
        await autosaveGate.waitUntilCompleted()

        #expect(store.notes.map(\.id) == [iCloudNote.id])
        #expect(store.selectedNoteID == nil)
        #expect(try iCloudRepository.loadNote(at: iCloudNote.url).markdown == "iCloud note")
        #expect(try localRepository.loadNote(at: localNote.url).markdown == "Old repository edit")
    }

    @Test
    func `pinning persists ordering and enforces the maximum`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        for index in 1...6 {
            _ = try harness.makeNote(markdown: "Note \(index)")
        }

        await harness.store.loadNotes()
        let candidates = harness.store.notes
        for candidate in candidates.prefix(NotePinning.maximumPinnedNotes) {
            await harness.store.togglePin(for: candidate)
        }

        let sixthCandidate = try #require(candidates.last)
        await harness.store.togglePin(for: sixthCandidate)

        #expect(harness.store.notes.filter(\.isPinned).count == NotePinning.maximumPinnedNotes)
        #expect(harness.store.errorMessage == "You can pin up to \(NotePinning.maximumPinnedNotes) notes.")
        #expect(try harness.repository.loadNote(at: sixthCandidate.url).metadata.pinnedAt == nil)

        let firstPinned = try #require(harness.store.notes.first)
        await harness.store.togglePin(for: firstPinned)
        await harness.store.togglePin(for: sixthCandidate)

        #expect(harness.store.notes.filter(\.isPinned).count == NotePinning.maximumPinnedNotes)
        #expect(try harness.repository.loadNote(at: sixthCandidate.url).metadata.pinnedAt != nil)
    }

    @Test
    func `deleting pinned note removes its persisted pin state`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        _ = try harness.makeNote(markdown: "Pinned")

        await harness.store.loadNotes()
        let summary = try #require(harness.store.notes.first)
        await harness.store.togglePin(for: summary)

        let pinnedSummary = try #require(harness.store.notes.first)
        #expect(pinnedSummary.isPinned)
        await harness.store.deleteNotes([pinnedSummary])

        #expect(harness.store.notes.isEmpty)
    }

    @Test
    func `stale title sort preference falls back to date edited`() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let suiteName = "Notra.NotesStoreTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults.set("title", forKey: "notes.sort.field")
        userDefaults.set(NoteSortDirection.oldestFirst.rawValue, forKey: "notes.sort.direction")

        let store = NotesStore(
            repository: TextBundleNoteRepository(rootURL: rootURL),
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: userDefaults)
        )

        #expect(store.sortPreference == NoteSortPreference(field: .dateEdited, direction: .oldestFirst))
    }

    @Test
    func `deleting linked attachment removes all markdown references`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }

        let note = try harness.makeNote(markdown: "")
        let importedAsset = try harness.repository.importImage(data: onePixelPNGData, into: note.url)
        let source = importedAsset.source
        var updatedNote = note
        updatedNote.markdown = "Before\n![One](\(source))\nAfter\n![Two](\(source))"
        try harness.repository.save(updatedNote)

        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        let attachment = try #require(harness.store.attachments.first)
        #expect(attachment.isLinked)
        await harness.store.deleteAttachment(attachment)

        #expect(!harness.store.editorText.contains(source))
        #expect(harness.store.attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: note.url.appendingPathComponent(source).path))
    }

    @Test
    func `adding tag updates metadata without changing markdown`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "Body")

        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        let tag = try #require(NoteTag("Swift"))
        let result = harness.store.addTag(tag)
        let loadedNote = try harness.repository.loadNote(at: note.url)

        #expect(result == .added(tag))
        #expect(harness.store.selectedNoteTags.map(\.name) == ["Swift"])
        #expect(loadedNote.markdown == "Body")
        #expect(loadedNote.metadata.tags.map(\.name) == ["Swift"])
        #expect(harness.store.notes.first { $0.id == note.id }?.tags.map(\.name) == ["Swift"])
    }

    @Test
    func `adding duplicate tag does not duplicate metadata`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "Body")

        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        let existingTag = try #require(NoteTag("Swift"))
        let duplicateTag = try #require(NoteTag("swift"))
        _ = harness.store.addTag(existingTag)
        let result = harness.store.addTag(duplicateTag)

        #expect(result == .duplicate(duplicateTag))
        #expect(harness.store.selectedNoteTags.map(\.name) == ["Swift"])
    }

    @Test
    func `removing tag updates metadata without changing markdown`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "Body")
        let tag = try #require(NoteTag("Swift"))

        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()
        _ = harness.store.addTag(tag)

        await harness.store.removeTag(tag)
        let loadedNote = try harness.repository.loadNote(at: note.url)

        #expect(harness.store.selectedNoteTags.isEmpty)
        #expect(loadedNote.markdown == "Body")
        #expect(loadedNote.metadata.tags.isEmpty)
        #expect(harness.store.notes.first { $0.id == note.id }?.tags.isEmpty == true)
    }

    private func makeHarness() throws -> NotesStoreHarness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let suiteName = "Notra.NotesStoreTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        let sortStorage = NoteSortPreferenceStorage(userDefaults: userDefaults)
        sortStorage.preference = NoteSortPreference(field: .dateCreated, direction: .oldestFirst)

        let repository = TextBundleNoteRepository(rootURL: rootURL)
        let searchIndex = SQLiteNoteSearchIndex(
            databaseURL: rootURL.appendingPathComponent("search.sqlite")
        )
        return NotesStoreHarness(
            repository: repository,
            store: NotesStore(
                repository: repository,
                sortPreferenceStorage: sortStorage,
                searchIndex: searchIndex,
                iCloudAvailability: { false }
            ),
            userDefaults: userDefaults,
            suiteName: suiteName
        )
    }

    private var onePixelPNGData: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }
}

private struct NotesStoreHarness {
    let repository: TextBundleNoteRepository
    let store: NotesStore
    let userDefaults: UserDefaults
    let suiteName: String

    func makeNote(markdown: String) throws -> Note {
        var note = try repository.createNote()
        note.markdown = markdown
        try repository.save(note)
        return note
    }

    func cleanup() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

private actor AutosavePauseGate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var completed = false
    private var completionWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else {
            return
        }

        await withCheckedContinuation { continuation in
            entryWaiter = continuation
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func markCompleted() {
        completed = true
        completionWaiter?.resume()
        completionWaiter = nil
    }

    func waitUntilCompleted() async {
        guard !completed else {
            return
        }

        await withCheckedContinuation { continuation in
            completionWaiter = continuation
        }
    }
}
