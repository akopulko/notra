import Foundation
@testable import Notra
import Testing

@MainActor
/// Exercises store selection, saving, deletion, import, and search synchronization behavior.
struct NotesStoreTests {
    @Test func deletingSelectedNoteSelectsPreviousNote() async throws {
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

    @Test func deletingFirstSelectedNoteSelectsNextNote() async throws {
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

    @Test func autosaveRefreshesNoteOrder() async throws {
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

        for _ in 0 ..< 60 {
            try await Task.sleep(for: .milliseconds(100))
            if harness.store.notes.first?.id == alpha.id {
                break
            }
        }

        #expect(harness.store.notes.first?.id == alpha.id)
        #expect(harness.store.notes.first?.previewText == "Edited")
    }

    @Test func contentSearchFindsBodyBeyondPreviewLine() async throws {
        let harness = try makeHarness()
        defer {
            harness.cleanup()
        }

        let note = try harness.makeNote(markdown: "Visible preview\n\nNeedle in body")

        await harness.store.loadNotes()
        for _ in 0 ..< 50 {
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

    @Test func deletingOnlySelectedNoteClearsEditorState() async throws {
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

    @Test func staleTitleSortPreferenceFallsBackToDateEdited() throws {
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

    @Test func deletingLinkedAttachmentRemovesAllMarkdownReferences() async throws {
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

    @Test func addingTagUpdatesMetadataWithoutChangingMarkdown() async throws {
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
    }

    @Test func addingDuplicateTagDoesNotDuplicateMetadata() async throws {
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

    @Test func removingTagUpdatesMetadataWithoutChangingMarkdown() async throws {
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
                searchIndex: searchIndex
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
