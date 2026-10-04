import Foundation
@testable import Notra
import Testing

struct NoteTagFilterTests {
    @Test
    func `available tags collapse equivalent spellings with stable labels and order`() throws {
        let swift = try #require(NoteTag("Swift"))
        let lowercaseSwift = try #require(NoteTag("swift"))
        let cafe = try #require(NoteTag("Café"))
        let plainCafe = try #require(NoteTag("cafe"))
        let first = try note("first", tags: [swift, cafe])
        let second = try note("second", tags: [lowercaseSwift, plainCafe])

        let forward = NoteTagFilter.availableTags(in: [first, second])
        let reverse = NoteTagFilter.availableTags(in: [second, first])

        #expect(forward.map(\.id) == reverse.map(\.id))
        #expect(forward.map(\.name) == reverse.map(\.name))
        #expect(Set(forward.map(\.id)) == [swift.id, cafe.id])
        #expect(forward.first { $0.id == swift.id }?.name == "Swift")
        #expect(forward.first { $0.id == cafe.id }?.name == "Café")
        #expect(NoteTagFilter.availableTags(in: []).isEmpty)
    }

    @Test
    func `selected tags match any selected tag`() throws {
        let alpha = try #require(NoteTag("alpha"))
        let beta = try #require(NoteTag("beta"))
        let alphaNote = try note("alpha-note", tags: [alpha])
        let betaNote = try note("beta-note", tags: [beta])
        let combinedNote = try note("combined-note", tags: [alpha, beta])
        let untaggedNote = try note("untagged-note", tags: [])

        let notes = [alphaNote, betaNote, combinedNote, untaggedNote]
        #expect(notes.filter { NoteTagFilter.matches($0, selectedIDs: []) }.map(\.id) == notes.map(\.id))
        #expect(notes.filter { NoteTagFilter.matches($0, selectedIDs: [alpha.id]) }.map(\.id) == [alphaNote.id, combinedNote.id])
        #expect(notes.filter { NoteTagFilter.matches($0, selectedIDs: [alpha.id, beta.id]) }.map(\.id) == [
            alphaNote.id, betaNote.id, combinedNote.id
        ])
        #expect(notes.filter { NoteTagFilter.matches($0, selectedIDs: [beta.id]) }.map(\.id) == [
            betaNote.id, combinedNote.id
        ])
    }

    @Test(arguments: [NoteSortDirection.latestFirst, .oldestFirst])
    func `tag filtering preserves pinned and date sort order`(direction: NoteSortDirection) throws {
        let tag = try #require(NoteTag("selected"))
        let newestPinned = try note(
            "pinned-new", tags: [tag], at: "2026-07-14T12:00:00Z", pinnedAt: "2026-07-14T12:00:00Z"
        )
        let olderPinned = try note(
            "pinned-old", tags: [tag], at: "2026-07-10T12:00:00Z", pinnedAt: "2026-07-13T12:00:00Z"
        )
        let newer = try note("regular-new", tags: [tag], at: "2026-07-12T12:00:00Z")
        let older = try note("regular-old", tags: [tag], at: "2026-06-01T12:00:00Z")
        let untagged = try note("excluded", tags: [], at: "2026-07-13T12:00:00Z")
        let sort = NoteSortPreference(field: .dateEdited, direction: direction)
        let ordered = NotePinning.pinnedFirst(sort.sorted([untagged, older, newer, olderPinned, newestPinned]))
        let filtered = ordered.filter { NoteTagFilter.matches($0, selectedIDs: [tag.id]) }
        let expectedRegular = direction == .latestFirst ? [newer.id, older.id] : [older.id, newer.id]
        #expect(filtered.map(\.id) == [newestPinned.id, olderPinned.id] + expectedRegular)

        let regularSections = NoteDateGrouping.sections(
            in: filtered.filter { !$0.isPinned },
            field: sort.field,
            now: try #require(ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")),
            calendar: Calendar(identifier: .gregorian)
        )
        let expectedSections = direction == .latestFirst ? [[newer.id], [older.id]] : [[older.id], [newer.id]]
        #expect(regularSections.map { $0.notes.map(\.id) } == expectedSections)
    }

    private func note(
        _ name: String,
        tags: [NoteTag],
        at timestamp: String = "2026-07-15T12:00:00Z",
        pinnedAt pinTimestamp: String? = nil
    ) throws -> NoteSummary {
        let date = try #require(ISO8601DateFormatter().date(from: timestamp))
        let pinDate = try pinTimestamp.map { try #require(ISO8601DateFormatter().date(from: $0)) }
        return NoteSummary(
            url: URL(fileURLWithPath: "/tmp/tag-filter-\(name).textbundle"),
            previewText: name,
            tags: tags,
            createdAt: date,
            modifiedAt: date,
            pinnedAt: pinDate
        )
    }
}
