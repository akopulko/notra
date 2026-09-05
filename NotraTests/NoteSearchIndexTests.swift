import Foundation
@testable import Notra
import Testing

@MainActor
/// Exercises full-text indexing, prefix/phrase search, updates, deletion, and pagination.
struct NoteSearchIndexTests {
    @Test func indexesMarkdownAndSupportsPrefixAndPhraseSearch() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }

        let first = try makeNote(
            markdown: "SwiftUI search uses an indexed phrase",
            in: repository
        )
        let second = try makeNote(
            markdown: "A different note contains unrelated content",
            in: repository
        )
        let index = makeIndex(for: repository)

        try await index.synchronize(noteIDs: [first.url, second.url])

        let prefixPage = try await index.search("swift", limit: 50, offset: 0)
        #expect(prefixPage.results.map(\.noteID) == [first.url.standardizedFileURL])

        let phrasePage = try await index.search("\"indexed phrase\"", limit: 50, offset: 0)
        #expect(phrasePage.results.map(\.noteID) == [first.url.standardizedFileURL])
    }

    @Test func updatesAndRemovesIndexedNotes() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }

        var note = try makeNote(markdown: "old searchable content", in: repository)
        let index = makeIndex(for: repository)
        try await index.synchronize(noteIDs: [note.url])

        var oldPage = try await index.search("old", limit: 50, offset: 0)
        #expect(oldPage.results.count == 1)

        note.markdown = "new searchable content"
        try repository.save(note)
        try await index.index(noteID: note.url, markdown: note.markdown, tags: [])

        oldPage = try await index.search("old", limit: 50, offset: 0)
        let newPage = try await index.search("new", limit: 50, offset: 0)
        #expect(oldPage.results.isEmpty)
        #expect(newPage.results.map(\.noteID) == [note.url.standardizedFileURL])

        try await index.remove(noteID: note.url)
        let removedPage = try await index.search("new", limit: 50, offset: 0)
        #expect(removedPage.results.isEmpty)
    }

    @Test func indexesTagsFromTextBundleMetadata() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }

        let note = try makeNote(markdown: "plain body", in: repository)
        try repository.updateNoteMetadata(
            NoteMetadata(tags: [try #require(NoteTag("architecture"))]),
            for: note.url
        )
        let index = makeIndex(for: repository)

        try await index.synchronize(noteIDs: [note.url])

        let page = try await index.search("architecture", limit: 50, offset: 0)
        #expect(page.results.map(\.noteID) == [note.url.standardizedFileURL])
    }

    @Test func filtersChecklistTagsAndLinkedAttachments() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }

        let checklist = try makeNote(markdown: "Needle\n- [ ] Buy milk", in: repository)
        let tagged = try makeNote(markdown: "Needle tag", in: repository)
        try repository.updateNoteMetadata(
            NoteMetadata(tags: [try #require(NoteTag("planning"))]),
            for: tagged.url
        )
        let attachment = try makeNote(markdown: "Needle attachment\n[File](assets/report.txt)", in: repository)
        let assetURL = attachment.url
            .appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true)
            .appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: assetURL)
        let plain = try makeNote(markdown: "Needle plain", in: repository)

        let index = makeIndex(for: repository)
        try await index.synchronize(noteIDs: [checklist.url, tagged.url, attachment.url, plain.url])

        let checklistPage = try await index.search("", filter: .checklists, limit: 50, offset: 0)
        #expect(checklistPage.results.map(\.noteID) == [checklist.url.standardizedFileURL])

        let taggedPage = try await index.search("", filter: .tags, limit: 50, offset: 0)
        #expect(taggedPage.results.map(\.noteID) == [tagged.url.standardizedFileURL])

        let attachmentPage = try await index.search("", filter: .attachments, limit: 50, offset: 0)
        #expect(attachmentPage.results.map(\.noteID) == [attachment.url.standardizedFileURL])

        let typedPage = try await index.search("needle", filter: .checklists, limit: 50, offset: 0)
        #expect(typedPage.results.map(\.noteID) == [checklist.url.standardizedFileURL])
    }

    @Test func limitsAndPagesResults() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }

        let notes = try (0 ..< 3).map { _ in
            try makeNote(markdown: "shared searchable term", in: repository)
        }
        let index = makeIndex(for: repository)
        try await index.synchronize(noteIDs: notes.map(\.url))

        let firstPage = try await index.search("shared", limit: 2, offset: 0)
        let secondPage = try await index.search("shared", limit: 2, offset: 2)

        #expect(firstPage.results.count == 2)
        #expect(firstPage.hasMore)
        #expect(secondPage.results.count == 1)
        #expect(!secondPage.hasMore)
        #expect(Set(firstPage.results.map(\.noteID)).isDisjoint(with: secondPage.results.map(\.noteID)))
    }

    @Test func rebuildRemovesStaleEntries() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }

        let first = try makeNote(markdown: "first indexed note", in: repository)
        let second = try makeNote(markdown: "second indexed note", in: repository)
        let index = makeIndex(for: repository)
        try await index.synchronize(noteIDs: [first.url, second.url])

        try repository.delete(NoteSummary(
            url: second.url,
            previewText: "Second",
            createdAt: second.createdAt,
            modifiedAt: second.modifiedAt
        ))
        try await index.rebuild(noteIDs: [first.url])

        let page = try await index.search("indexed", limit: 50, offset: 0)
        #expect(page.results.map(\.noteID) == [first.url.standardizedFileURL])
    }

    private func makeRepository() throws -> TextBundleNoteRepository {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return TextBundleNoteRepository(rootURL: rootURL)
    }

    private func makeIndex(for repository: TextBundleNoteRepository) -> SQLiteNoteSearchIndex {
        SQLiteNoteSearchIndex(
            databaseURL: repository.rootURL.appendingPathComponent("search.sqlite")
        )
    }

    private func makeNote(
        markdown: String,
        in repository: TextBundleNoteRepository
    ) throws -> Note {
        var note = try repository.createNote()
        note.markdown = markdown
        try repository.save(note)
        return note
    }
}
