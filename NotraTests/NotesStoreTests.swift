import Foundation
@testable import Notra
import Testing

/// Exercises store selection, saving, deletion, import, and search synchronization behavior.
@MainActor
struct NotesStoreTests {
    @Test
    func `loading notes leaves selection empty until explicitly selected`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let firstNote = try harness.makeNote(markdown: "First note")

        await harness.store.loadNotes()

        #expect(harness.store.notes.map(\.id) == [firstNote.id])
        #expect(harness.store.selectedNoteID == nil)
        #expect(!harness.store.hasSelection)
        #expect(harness.store.editorText.isEmpty)

        harness.store.selectedNoteID = firstNote.id
        await harness.store.selectionChanged()

        #expect(harness.store.editorText == firstNote.markdown)
    }

    @Test
    func `selection preserves unedited note timestamps and order`() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let alpha = try harness.makeNote(markdown: "Alpha")
        let beta = try harness.makeNote(markdown: "Beta")
        try setModificationDates(of: alpha, to: Date(timeIntervalSince1970: 946684800))
        try setModificationDates(of: beta, to: Date(timeIntervalSince1970: 978307200))
        let alphaDates = try modificationDates(of: alpha)
        let betaDates = try modificationDates(of: beta)

        await harness.store.loadNotes()
        harness.store.setSortField(.dateEdited)
        harness.store.setSortDirection(.latestFirst)
        let initialSummaries = harness.store.notes
        #expect(initialSummaries.map(\.id) == [beta.id, alpha.id])
        for noteID in [alpha.id, beta.id, alpha.id] {
            harness.store.selectedNoteID = noteID
            await harness.store.selectionChanged()
        }

        #expect(try modificationDates(of: alpha) == alphaDates)
        #expect(try modificationDates(of: beta) == betaDates)
        #expect(try harness.repository.loadNote(at: alpha.url).markdown == "Alpha")
        #expect(try harness.repository.loadNote(at: beta.url).markdown == "Beta")
        #expect(harness.store.notes == initialSummaries)
    }

    @Test
    func `selection flushes pending edits without touching the destination`() async throws {
        let gate = AutosavePauseGate()
        let harness = try makeHarness(
            autosavePause: { await gate.pause() },
            autosaveCompletion: { await gate.markCompleted() }
        )
        defer { harness.cleanup() }
        let alpha = try harness.makeNote(markdown: "Alpha")
        let beta = try harness.makeNote(markdown: "Beta")
        try setModificationDates(of: alpha, to: Date(timeIntervalSince1970: 946684800))
        try setModificationDates(of: beta, to: Date(timeIntervalSince1970: 978307200))
        let alphaDates = try modificationDates(of: alpha)
        let betaDates = try modificationDates(of: beta)
        await harness.store.loadNotes()
        harness.store.selectedNoteID = alpha.id
        await harness.store.selectionChanged()
        harness.store.updateEditorText("Edited Alpha")
        await gate.waitUntilEntered()

        harness.store.selectedNoteID = beta.id
        await harness.store.selectionChanged()
        let savedDates = try modificationDates(of: alpha)
        await gate.release()
        await gate.waitUntilCompleted()

        #expect(try harness.repository.loadNote(at: alpha.url).markdown == "Edited Alpha")
        #expect(savedDates.text > alphaDates.text)
        #expect(try modificationDates(of: alpha) == savedDates)
        #expect(try modificationDates(of: beta) == betaDates)
        #expect(harness.store.editorText == "Beta")
        #expect(harness.store.notes.first { $0.id == alpha.id }?.modifiedAt == savedDates.text)
    }

    @Test
    func `selection does not rewrite an autosaved note`() async throws {
        let gate = AutosavePauseGate()
        let harness = try makeHarness(
            autosavePause: { await gate.pause() },
            autosaveCompletion: { await gate.markCompleted() }
        )
        defer { harness.cleanup() }
        let alpha = try harness.makeNote(markdown: "Alpha")
        let beta = try harness.makeNote(markdown: "Beta")
        try setModificationDates(of: alpha, to: Date(timeIntervalSince1970: 946684800))
        await harness.store.loadNotes()
        harness.store.selectedNoteID = alpha.id
        await harness.store.selectionChanged()
        harness.store.updateEditorText("Autosaved Alpha")
        await gate.waitUntilEntered()
        await gate.release()
        await gate.waitUntilCompleted()
        let savedDates = try modificationDates(of: alpha)
        #expect(try harness.repository.loadNote(at: alpha.url).markdown == "Autosaved Alpha")

        harness.store.selectedNoteID = beta.id
        await harness.store.selectionChanged()
        #expect(try modificationDates(of: alpha) == savedDates)
        #expect(harness.store.editorText == "Beta")
    }

    @Test
    func `explicit saves write only changed content`() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let alpha = try harness.makeNote(markdown: "Alpha")
        let beta = try harness.makeNote(markdown: "Beta")
        try setModificationDates(of: alpha, to: Date(timeIntervalSince1970: 946684800))
        let originalDates = try modificationDates(of: alpha)
        await harness.store.loadNotes()
        harness.store.selectedNoteID = alpha.id
        await harness.store.selectionChanged()

        await harness.store.saveNow()
        #expect(try modificationDates(of: alpha) == originalDates)
        harness.store.updateEditorText("Saved Alpha")
        await harness.store.saveNow()
        let savedDates = try modificationDates(of: alpha)
        #expect(savedDates.text > originalDates.text)
        #expect(try harness.repository.loadNote(at: alpha.url).markdown == "Saved Alpha")

        await harness.store.saveNow()
        harness.store.selectedNoteID = beta.id
        await harness.store.selectionChanged()
        #expect(try modificationDates(of: alpha) == savedDates)
    }

    @Test
    func `cancelled autosave preserves the newer explicit save baseline`() async throws {
        let gate = AutosavePauseGate()
        let completions = AutosaveCompletionCounter()
        let harness = try makeHarness(
            autosavePause: { await gate.pause() },
            autosaveCompletion: { await completions.markCompleted() }
        )
        defer { harness.cleanup() }
        let alpha = try harness.makeNote(markdown: "Alpha")
        let beta = try harness.makeNote(markdown: "Beta")
        await harness.store.loadNotes()
        harness.store.selectedNoteID = alpha.id
        await harness.store.selectionChanged()
        harness.store.updateEditorText("Older edit")
        await gate.waitUntilEntered()
        harness.store.updateEditorText("Newer edit")
        await harness.store.saveNow()
        let savedDates = try modificationDates(of: alpha)
        await gate.release()
        await completions.waitUntilCompleted(count: 2)

        harness.store.selectedNoteID = beta.id
        await harness.store.selectionChanged()
        #expect(try harness.repository.loadNote(at: alpha.url).markdown == "Newer edit")
        #expect(try modificationDates(of: alpha) == savedDates)
        #expect(harness.store.editorText == "Beta")
    }

    @Test
    func `failed explicit save leaves edits pending for retry`() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let alpha = try harness.makeNote(markdown: "Alpha")
        await harness.store.loadNotes()
        harness.store.selectedNoteID = alpha.id
        await harness.store.selectionChanged()
        harness.store.updateEditorText("Pending edit")
        let textURL = alpha.url.appendingPathComponent(TextBundleNoteRepository.textFilename)
        let backupURL = alpha.url.appendingPathComponent("original.md")
        try FileManager.default.moveItem(at: textURL, to: backupURL)
        try FileManager.default.createDirectory(at: textURL, withIntermediateDirectories: false)
        await harness.store.saveNow()
        #expect(harness.store.errorMessage != nil)
        try FileManager.default.removeItem(at: textURL)
        try FileManager.default.moveItem(at: backupURL, to: textURL)

        await harness.store.saveNow()
        #expect(try harness.repository.loadNote(at: alpha.url).markdown == "Pending edit")
        let savedDates = try modificationDates(of: alpha)
        await harness.store.saveNow()
        #expect(try modificationDates(of: alpha) == savedDates)
    }

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
    func `preview task toggle updates selected markdown and persists`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "- [ ] Complete this task")

        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()
        harness.store.toggleTask(
            MarkdownTaskMarker(line: 1, column: 3, state: .unchecked),
            to: .checked
        )

        #expect(harness.store.editorText == "- [x] Complete this task")
        await harness.store.saveNow()
        #expect(try harness.repository.loadNote(at: note.url).markdown == "- [x] Complete this task")
    }

    @Test
    func `content search finds body beyond preview line`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }

        let note = try harness.makeNote(markdown: "Visible preview\n\nNeedle in body")

        await harness.store.loadNotes()
        try await waitUntilSearchReady(harness.store)

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
    func `library loading publishes notes only after the background read completes`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "Background note")
        let gate = RepositoryLibraryLoadGate(delayedRootURL: harness.repository.rootURL)
        let store = NotesStore(
            repository: harness.repository,
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: harness.userDefaults),
            searchIndex: SQLiteNoteSearchIndex(
                databaseURL: harness.repository.rootURL.appendingPathComponent("background-search.sqlite")
            ),
            storagePreferenceStorage: NoteStoragePreferenceStorage(userDefaults: harness.userDefaults),
            libraryNotesLoader: { repository, sortPreference in
                try await gate.load(repository: repository, sortPreference: sortPreference)
            },
            iCloudAvailability: { false }
        )

        let loadTask = Task { @MainActor in
            await store.loadNotes()
        }
        await gate.waitUntilEntered()

        #expect(store.isLoading)
        #expect(store.notes.isEmpty)

        await gate.release()
        await loadTask.value

        #expect(store.notes.map(\.id) == [note.id])
        #expect(!store.isLoading)
    }

    @Test
    func `stale initial library load cannot overwrite a storage switch`() async throws {
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
        let suiteName = "Notra.NotesStoreLibraryLoadTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let gate = RepositoryLibraryLoadGate(delayedRootURL: localRepository.rootURL)
        let store = NotesStore(
            repository: localRepository,
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: userDefaults),
            searchIndex: SQLiteNoteSearchIndex(
                databaseURL: localRootURL.appendingPathComponent("background-search.sqlite")
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
            libraryNotesLoader: { repository, sortPreference in
                try await gate.load(repository: repository, sortPreference: sortPreference)
            },
            iCloudAvailability: { true }
        )

        let initialLoadTask = Task { @MainActor in
            await store.loadNotes()
        }
        await gate.waitUntilEntered()

        await store.changeStorageLocation(to: .iCloud)
        await gate.release()
        await initialLoadTask.value

        #expect(store.storageLocation == .iCloud)
        #expect(store.notes.map(\.id) == [iCloudNote.id])
        #expect(!store.notes.contains(where: { $0.id == localNote.id }))
        #expect(!store.isLoading)
    }

    @Test
    func `library byte count follows active storage and rejects stale reads`() async throws {
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
        try Data(repeating: 1, count: 24)
            .write(to: localRootURL.appendingPathComponent("local-search.sqlite"))
        try Data(repeating: 2, count: 48)
            .write(to: iCloudRootURL.appendingPathComponent("iCloud-search.sqlite"))

        let suiteName = "Notra.NotesStoreLibraryByteCountTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let gate = RepositoryLibraryLoadGate(delayedRootURL: localRepository.rootURL)
        let store = NotesStore(
            repository: localRepository,
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: userDefaults),
            searchIndex: SQLiteNoteSearchIndex(
                databaseURL: localRootURL.appendingPathComponent("byte-count-search.sqlite")
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
            libraryByteCountLoader: { repository in
                try await gate.loadByteCount(repository: repository)
            },
            iCloudAvailability: { true }
        )

        let localByteCount = try await store.loadLibraryByteCount()
        let expectedLocalByteCount = localRepository.totalBundleSize(at: localNote.url)
        #expect(localByteCount == expectedLocalByteCount)

        await gate.delayNextByteCountLoad()
        let staleRequest = Task { @MainActor in
            try await store.loadLibraryByteCount()
        }
        await gate.waitUntilEntered()

        await store.changeStorageLocation(to: .iCloud)
        await gate.release()

        do {
            _ = try await staleRequest.value
            Issue.record("Expected the stale library byte-count request to be cancelled.")
        } catch is CancellationError {
            // Expected after switching the active repository.
        } catch {
            Issue.record("Expected CancellationError, got \(error).")
        }

        let iCloudByteCount = try await store.loadLibraryByteCount()
        let expectedICloudByteCount = iCloudRepository.totalBundleSize(at: iCloudNote.url)
        #expect(iCloudByteCount == expectedICloudByteCount)
    }

    @Test
    func `cancelled library loading does not show an error`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let store = NotesStore(
            repository: harness.repository,
            sortPreferenceStorage: NoteSortPreferenceStorage(userDefaults: harness.userDefaults),
            searchIndex: SQLiteNoteSearchIndex(
                databaseURL: harness.repository.rootURL.appendingPathComponent("cancelled-search.sqlite")
            ),
            storagePreferenceStorage: NoteStoragePreferenceStorage(userDefaults: harness.userDefaults),
            libraryNotesLoader: { _, _ in
                throw CancellationError()
            },
            iCloudAvailability: { false }
        )

        await store.loadNotes()

        #expect(store.errorMessage == nil)
        #expect(!store.isLoading)
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

        try await waitUntilSearchReady(store)
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
            repositoryNotesLoader: { _, _ in
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
    func `linking unlinked image appends preview markdown at bottom and updates link state`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }

        let note = try harness.makeNote(markdown: "Body")
        let importedAsset = try harness.repository.importImage(data: onePixelPNGData, into: note.url)

        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        let attachment = try #require(harness.store.attachments.first)
        #expect(!attachment.isLinked)
        harness.store.linkAttachment(attachment)

        #expect(harness.store.editorText == "Body\n![](\(importedAsset.source))\n")
        #expect(harness.store.attachments.first?.isLinked == true)

        await harness.store.saveNow()
        #expect(try harness.repository.loadNote(at: note.url).markdown == harness.store.editorText)
    }

    @Test
    func `unlinking linked attachment removes references without deleting asset`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }

        let note = try harness.makeNote(markdown: "")
        let importedAsset = try harness.repository.importImage(data: onePixelPNGData, into: note.url)
        var updatedNote = note
        updatedNote.markdown = "Before\n![One](\(importedAsset.source))\nAfter\n![Two](\(importedAsset.source))"
        try harness.repository.save(updatedNote)

        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        let attachment = try #require(harness.store.attachments.first)
        #expect(attachment.isLinked)
        harness.store.unlinkAttachment(attachment)

        #expect(!harness.store.editorText.contains(importedAsset.source))
        #expect(
            FileManager.default.fileExists(
                atPath: note.url.appendingPathComponent(importedAsset.source).path
            )
        )
        #expect(harness.store.attachments.first?.isLinked == false)

        await harness.store.saveNow()
        let loadedNote = try harness.repository.loadNote(at: note.url)
        #expect(!loadedNote.markdown.contains(importedAsset.source))
    }

    @Test
    func `attachment projection publishes stored byte count`() async throws {
        let harness = try makeHarness()
        let byteCount = 4_096
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).bin")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            harness.cleanup()
        }
        try Data(repeating: 1, count: byteCount).write(to: sourceURL)

        let note = try harness.makeNote(markdown: "")
        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()

        let importedAsset = try harness.store.importAttachment(
            from: sourceURL,
            maximumByteCount: Int64(byteCount)
        )
        #expect(harness.store.attachments.first?.byteCount == Int64(byteCount))

        harness.store.updateEditorText("[Attachment](\(importedAsset.source))")
        await harness.store.saveNow()

        let attachment = try #require(harness.store.attachments.first)
        #expect(attachment.byteCount == Int64(byteCount))
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
        #expect(NoteTagFilter.availableTags(in: harness.store.notes).map(\.name) == ["Swift"])
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
        #expect(NoteTagFilter.availableTags(in: harness.store.notes).isEmpty)
        #expect(harness.store.notes.first { $0.id == note.id }?.tags.isEmpty == true)
    }

    @Test
    func `deleting last tagged note removes its derived choice`() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }
        let note = try harness.makeNote(markdown: "Body")
        let tag = try #require(NoteTag("last-tag"))

        await harness.store.loadNotes()
        harness.store.selectedNoteID = note.id
        await harness.store.selectionChanged()
        _ = harness.store.addTag(tag)
        #expect(NoteTagFilter.availableTags(in: harness.store.notes).map(\.id) == [tag.id])

        let summary = try #require(harness.store.notes.first { $0.id == note.id })
        await harness.store.deleteNotes([summary])
        #expect(NoteTagFilter.availableTags(in: harness.store.notes).isEmpty)
    }

#if os(macOS)
    @Test
    func `importing Markdown creates independent notes and indexes their bodies`() async throws {
        let harness = try makeHarness()
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            harness.cleanup()
            try? FileManager.default.removeItem(at: harness.repository.rootURL)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }

        let alphaBody = "# Alpha\n\nuniquealpha café\n"
        let betaBody = "# Beta\n\nuniquebeta\n"
        let alphaURL = sourceDirectory.appendingPathComponent("alpha.md")
        let betaURL = sourceDirectory.appendingPathComponent("beta.markdown")
        try Data(alphaBody.utf8).write(to: alphaURL)
        try Data(betaBody.utf8).write(to: betaURL)

        await harness.store.loadNotes()
        let firstResult = await harness.store.importNotes(from: [alphaURL, betaURL])
        let importedSummaries = harness.store.notes
        #expect(importedSummaries.count == 2)
        let alphaSummary = try #require(importedSummaries.first { $0.previewText.contains("uniquealpha") })
        let betaSummary = try #require(importedSummaries.first { $0.previewText.contains("uniquebeta") })
        #expect(alphaSummary.id != betaSummary.id)
        #expect(try harness.repository.loadNote(at: alphaSummary.url).markdown == alphaBody)
        #expect(try harness.repository.loadNote(at: betaSummary.url).markdown == betaBody)
        #expect(harness.store.selectedNoteID == betaSummary.id)
        #expect(firstResult == betaSummary.id)
        #expect(harness.store.editorText == betaBody)
        #expect(try Data(contentsOf: alphaURL) == Data(alphaBody.utf8))
        #expect(try Data(contentsOf: betaURL) == Data(betaBody.utf8))

        let repeatedURL = await harness.store.importNotes(from: [alphaURL])
        #expect(repeatedURL != nil)
        #expect(repeatedURL != alphaSummary.id)
        #expect(harness.store.notes.count == 3)
        #expect(try harness.repository.loadNote(at: alphaSummary.url).markdown == alphaBody)
        #expect(try harness.repository.loadNote(at: try #require(repeatedURL)).markdown == alphaBody)

        try await waitUntilSearchReady(harness.store)
        let alphaSearch = await harness.store.searchNotes(query: "uniquealpha", limit: 20, offset: 0)
        let betaSearch = await harness.store.searchNotes(query: "uniquebeta", limit: 20, offset: 0)
        #expect(alphaSearch?.results.contains(where: { $0.noteID == alphaSummary.id }) == true)
        #expect(betaSearch?.results.contains(where: { $0.noteID == betaSummary.id }) == true)
    }

    @Test
    func `importing Markdown saves pending edits before switching selection`() async throws {
        let harness = try makeHarness()
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            harness.cleanup()
            try? FileManager.default.removeItem(at: harness.repository.rootURL)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }

        let original = try harness.makeNote(markdown: "unsaved old")
        let sourceURL = sourceDirectory.appendingPathComponent("import.md")
        try Data("# Imported\n\nimported body".utf8).write(to: sourceURL)
        await harness.store.loadNotes()
        harness.store.selectedNoteID = original.id
        await harness.store.selectionChanged()
        harness.store.updateEditorText("unsaved original")

        let importedURL = await harness.store.importNotes(from: [sourceURL])

        #expect(try harness.repository.loadNote(at: original.url).markdown == "unsaved original")
        #expect(harness.store.selectedNoteID == importedURL)
        #expect(harness.store.editorText == "# Imported\n\nimported body")
    }

    @Test
    func `importing Markdown continues after missing and invalid UTF8 sources`() async throws {
        let harness = try makeHarness()
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            harness.cleanup()
            try? FileManager.default.removeItem(at: harness.repository.rootURL)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }

        let alphaBody = "# Alpha\n\nuniquealpha café\n"
        let betaBody = "# Beta\n\nuniquebeta\n"
        let alphaURL = sourceDirectory.appendingPathComponent("alpha.md")
        let missingURL = sourceDirectory.appendingPathComponent("missing.md")
        let invalidURL = sourceDirectory.appendingPathComponent("invalid.md")
        let betaURL = sourceDirectory.appendingPathComponent("beta.md")
        try Data(alphaBody.utf8).write(to: alphaURL)
        try Data([0xFF, 0xFE, 0xFF]).write(to: invalidURL)
        try Data(betaBody.utf8).write(to: betaURL)

        await harness.store.loadNotes()
        let selectedURL = await harness.store.importNotes(from: [alphaURL, missingURL, invalidURL, betaURL])

        #expect(harness.store.notes.count == 2)
        #expect(harness.store.notes.allSatisfy { !$0.previewText.contains("missing") && !$0.previewText.contains("invalid") })
        #expect(harness.store.notes.contains { $0.previewText.contains("uniquealpha") })
        #expect(harness.store.notes.contains { $0.previewText.contains("uniquebeta") })
        #expect(harness.store.selectedNoteID == selectedURL)
        #expect(harness.store.errorMessage?.contains("missing.md") == true)
        #expect(harness.store.errorMessage?.contains("invalid.md") == true)
    }

    @Test
    func `importing an empty Markdown file creates an empty note and rejects inactive batches`() async throws {
        let harness = try makeHarness()
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            harness.cleanup()
            try? FileManager.default.removeItem(at: harness.repository.rootURL)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }

        let existing = try harness.makeNote(markdown: "Existing")
        let emptyURL = sourceDirectory.appendingPathComponent("empty.md")
        try Data().write(to: emptyURL)
        await harness.store.loadNotes()
        harness.store.selectedNoteID = existing.id
        await harness.store.selectionChanged()
        let initialIDs = harness.store.notes.map(\.id)
        let initialSelection = harness.store.selectedNoteID

        #expect(await harness.store.importNotes(from: []) == nil)
        harness.store.isChangingStorage = true
        #expect(await harness.store.importNotes(from: [emptyURL]) == nil)
        harness.store.isChangingStorage = false
        #expect(harness.store.notes.map(\.id) == initialIDs)
        #expect(harness.store.selectedNoteID == initialSelection)

        let importedURL = await harness.store.importNotes(from: [emptyURL])
        let importedNote = try harness.repository.loadNote(at: try #require(importedURL))
        #expect(importedNote.markdown.isEmpty)
        #expect(harness.store.editorText.isEmpty)
        #expect(harness.store.notes.count == 2)
    }
#endif

    private func waitUntilSearchReady(_ store: NotesStore) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while store.searchStatus != .ready,
              store.searchStatus != .unavailable,
              clock.now < deadline
        {
            try await clock.sleep(for: .milliseconds(10))
        }
        try #require(
            store.searchStatus == .ready,
            "Search index did not become ready before the deadline or became unavailable."
        )
    }

    private func makeHarness(
        autosavePause: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(500))
        },
        autosaveCompletion: @escaping @Sendable () async -> Void = {}
    ) throws -> NotesStoreHarness {
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
                iCloudAvailability: { false },
                autosavePause: autosavePause,
                autosaveCompletion: autosaveCompletion
            ),
            userDefaults: userDefaults,
            suiteName: suiteName
        )
    }

    private func setModificationDates(of note: Note, to date: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: note.url.appendingPathComponent(TextBundleNoteRepository.textFilename).path
        )
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: note.url.path)
    }

    private func modificationDates(of note: Note) throws -> NoteModificationDates {
        let textAttributes = try FileManager.default.attributesOfItem(
            atPath: note.url.appendingPathComponent(TextBundleNoteRepository.textFilename).path
        )
        let bundleAttributes = try FileManager.default.attributesOfItem(atPath: note.url.path)
        return try NoteModificationDates(
            text: #require(textAttributes[.modificationDate] as? Date),
            bundle: #require(bundleAttributes[.modificationDate] as? Date)
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

/// Holds one repository read open so tests can deterministically exercise stale-result handling.
private actor RepositoryLibraryLoadGate {
    private let delayedRootURL: URL
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var byteCountDelayEnabled = false

    init(delayedRootURL: URL) {
        self.delayedRootURL = delayedRootURL
    }

    func load(
        repository: TextBundleNoteRepository,
        sortPreference: NoteSortPreference
    ) async throws -> [NoteSummary] {
        if repository.rootURL == delayedRootURL {
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
            }
        }

        return try sortPreference.sorted(repository.listNotes())
    }

    func delayNextByteCountLoad() {
        byteCountDelayEnabled = true
        entered = false
    }

    func loadByteCount(repository: TextBundleNoteRepository) async throws -> Int64 {
        if repository.rootURL == delayedRootURL && byteCountDelayEnabled {
            byteCountDelayEnabled = false
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
            }
        }

        return try await NoteLibraryLoader.totalByteCount(repository: repository)
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

private struct NoteModificationDates: Equatable {
    let text: Date
    let bundle: Date
}

private actor AutosaveCompletionCounter {
    private var count = 0
    private var target = 0
    private var waiter: CheckedContinuation<Void, Never>?

    func markCompleted() {
        count += 1
        if count >= target {
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilCompleted(count target: Int) async {
        guard count < target else { return }
        self.target = target
        await withCheckedContinuation { waiter = $0 }
    }
}
