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

    @Test
    func `available tags rank by note membership independent of input order`() throws {
        let zeta = try #require(NoteTag("zeta"))
        let beta = try #require(NoteTag("beta"))
        let alpha = try #require(NoteTag("alpha"))
        let gamma = try #require(NoteTag("gamma"))
        let notes = [
            try note("zeta-one", tags: [zeta]),
            try note("zeta-two", tags: [beta, zeta]),
            try note("zeta-three", tags: [gamma, alpha, zeta]),
            try note("beta-two", tags: [beta])
        ]

        let reversedNotes = [
            try note("beta-two", tags: [beta]),
            try note("zeta-three", tags: [zeta, alpha, gamma]),
            try note("zeta-two", tags: [zeta, beta]),
            try note("zeta-one", tags: [zeta])
        ]
        let forward = NoteTagFilter.availableTags(in: notes)
        let reversed = NoteTagFilter.availableTags(in: reversedNotes)
        #expect(forward.map(\.id) == [zeta.id, beta.id, alpha.id, gamma.id])
        #expect(reversed.map(\.id) == forward.map(\.id))
        #expect(reversed.map(\.name) == forward.map(\.name))
    }

    @Test
    func `available tags count normalized membership once per note`() throws {
        let swift = try #require(NoteTag("Swift"))
        let lowercaseSwift = try #require(NoteTag("swift"))
        let zeta = try #require(NoteTag("zeta"))
        let notes = [
            try note("duplicates", tags: [swift, lowercaseSwift, lowercaseSwift]),
            try note("swift-two", tags: [lowercaseSwift]),
            try note("zeta-one", tags: [zeta]),
            try note("zeta-two", tags: [zeta]),
            try note("zeta-three", tags: [zeta])
        ]
        let ranked = NoteTagFilter.availableTags(in: notes)
        #expect(ranked.map(\.id) == [zeta.id, swift.id])
        #expect(ranked.last?.name == "Swift")
    }

    @Test
    func `available tags retains all ranks beyond collapsed display boundary`() throws {
        let tags = try (1...12).map { try #require(NoteTag(String(format: "tag-%02d", $0))) }
        let notes = try (0..<12).map { noteIndex in
            try note(
                "rank-\(noteIndex)",
                tags: Array(tags.prefix(12 - noteIndex).reversed())
            )
        }
        let ranked = NoteTagFilter.availableTags(in: notes.reversed().map { $0 })
        let expectedIDs = tags.map(\.id)
        #expect(ranked.map(\.id) == expectedIDs)
        #expect(Array(ranked.prefix(10)).map(\.id) == Array(expectedIDs.prefix(10)))
    }

    @Test
    func `available tags preserves filtering beyond expanded display boundary`() throws {
        let tags = try (1...101).map { try #require(NoteTag(String(format: "tag-%03d", $0))) }
        let note = try self.note("all-tags", tags: tags.reversed())
        let ranked = NoteTagFilter.availableTags(in: [note])
        #expect(ranked.map(\.id) == tags.map(\.id))
        #expect(NoteTagFilter.matches(note, selectedIDs: [tags[100].id]))
    }

    @Test
    func `note metadata enforces the per-note tag limit`() throws {
        let tags = try (1...NoteMetadata.maximumTagsPerNote + 1).map {
            try #require(NoteTag("tag-\($0)"))
        }
        var metadata = NoteMetadata(tags: tags)

        #expect(metadata.tags == Array(tags.prefix(NoteMetadata.maximumTagsPerNote)))
        #expect(metadata.add(tags[0]) == .duplicate(tags[0]))
        #expect(metadata.add(tags[NoteMetadata.maximumTagsPerNote]) == .limitReached)
        #expect(metadata.tags.count == NoteMetadata.maximumTagsPerNote)
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
